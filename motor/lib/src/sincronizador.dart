// O SINCRONIZADOR: um ciclo para todos os pares do computador.
//
//   1. lê o diário de cada par (sem diário → junção segura + base do servidor);
//   2. confere a raiz (pasta e marcador) — sumiu: o par PARA, nada é apagado;
//   3. atualiza a árvore da nuvem: listagem inicial paginada ou UMA consulta
//      de mudanças para todos os pares;
//   4. varre a pasta local; 5. planeja; 6. freia a EXCLUSÃO EM MASSA;
//   7. executa (até 3 transferências ao mesmo tempo); 8. grava o diário,
//      replica a base e o histórico no servidor, atualiza a situação do par.
//
// ⚠️ A base de cada arquivo só muda DEPOIS do efeito confirmado no disco e no
// servidor. Um ciclo interrompido no meio (energia, kill) recomeça do diário:
// o pior caso é refazer uma transferência, nunca perder um arquivo.
import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import 'api.dart';
import 'diario.dart';
import 'ignorados.dart';
import 'impressao.dart';
import 'modelos.dart';
import 'nomes.dart';
import 'planejador.dart';
import 'varredura.dart';

const String pastaLixeiraLocal = '.nncloud-lixeira';

/// O PHP codifica um array vazio como `[]`, não `{}`: aceita os dois.
Map<String, dynamic> _mapa(dynamic v) => v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};

class ConfigPar {
  final int id;
  final String raiz;          // caminho absoluto da pasta no computador
  final int espacoId;
  final int? raizId;          // pasta da nuvem (null = o espaço inteiro)
  final String nome;
  bool pausado;
  ConfigPar({required this.id, required this.raiz, required this.espacoId, this.raizId, this.nome = '', this.pausado = false});
}

/// Exclusões que passam do limite e esperam a pessoa confirmar.
class ExclusaoEmMassa {
  final int par;
  final int naNuvem, noComputador, total;
  final List<String> exemplos;
  ExclusaoEmMassa(this.par, this.naNuvem, this.noComputador, this.total, this.exemplos);
}

class Evento {
  final String tipo;       // enviado, baixado, conflito, problema, erro, progresso, pausado…
  final int? par;
  final String? caminho;
  final String? detalhe;
  final int? tamanho;
  const Evento(this.tipo, {this.par, this.caminho, this.detalhe, this.tamanho});
  @override
  String toString() => 'Evento($tipo ${par ?? ''} ${caminho ?? ''} ${detalhe ?? ''})';
}

class ResultadoPar {
  final int par;
  String estado = 'ok';          // ok, pausado, erro, aguardando_confirmacao, offline
  String? mensagem;
  int enviados = 0, baixados = 0, conflitos = 0, excluidos = 0, erros = 0, pendentes = 0;
  final List<String> problemas = [];
  ExclusaoEmMassa? exclusao;
  ResultadoPar(this.par);
}

class Sincronizador {
  final Api api;
  final Directory dados;          // pasta de dados do aplicativo
  final String computador;
  final Ignorados ignorados;
  final void Function(Evento)? aoEvento;
  /// Limites da exclusão em massa (por ciclo, por par).
  final int limiteExclusoes;
  final double limiteFracao;
  /// Exclusões em massa já confirmadas pela pessoa (par → até quando vale).
  final Map<int, DateTime> confirmadas = {};
  final int paralelo;

  /// Varredura completa no máximo a cada [intervaloVarredura] quando nada
  /// avisou (o observador de arquivos marca o par como "sujo").
  final Duration intervaloVarredura;
  final Map<int, DateTime> _ultimaVarredura = {};
  final Set<int> _sujos = {};
  final Set<int> _nuvemMudou = {};

  final Map<int, Diario> _diarios = {};
  final List<Map<String, dynamic>> _historico = [];
  final Random _rnd = Random.secure();

  Sincronizador({
    required this.api,
    required this.dados,
    required this.computador,
    Ignorados? ignorados,
    this.aoEvento,
    this.limiteExclusoes = 50,
    this.limiteFracao = 0.25,
    this.paralelo = 3,
    this.intervaloVarredura = const Duration(minutes: 10),
  }) : ignorados = ignorados ?? Ignorados();

  /// O observador viu algo mudar nesta pasta: varre no próximo ciclo.
  void marcarSujo(int par) => _sujos.add(par);

  /// Força a varredura de todos (ex.: o computador acordou da suspensão).
  void marcarTodosSujos() => _ultimaVarredura.clear();

  Directory _pastaPar(int par) => Directory(p.join(dados.path, 'pares', '$par'));

  void _ev(Evento e) => aoEvento?.call(e);

  /// Libera as exclusões em massa daquele par pelos próximos 10 minutos.
  void confirmarExclusoes(int par) => confirmadas[par] = DateTime.now().add(const Duration(minutes: 10));

  // =====================================================================
  // Ciclo
  // =====================================================================

  Future<List<ResultadoPar>> ciclo(List<ConfigPar> pares) async {
    final res = <int, ResultadoPar>{for (final c in pares) c.id: ResultadoPar(c.id)};
    final ativos = <ConfigPar>[];
    for (final c in pares) {
      final r = res[c.id]!;
      if (c.pausado) {
        r.estado = 'pausado';
        continue;
      }
      final d = await _diario(c);
      final sit = Varredura.conferirRaiz(c.raiz, c.id);
      if (sit == SituacaoRaiz.semMarcador && d.base.isEmpty && Directory(c.raiz).existsSync()) {
        Varredura.gravarMarcador(c.raiz, c.id);   // primeira vez: a pasta passa a ser do par
      } else if (sit != SituacaoRaiz.ok) {
        r.estado = 'erro';
        r.mensagem = switch (sit) {
          SituacaoRaiz.semRaiz => 'A pasta "${c.raiz}" não foi encontrada (disco desconectado, pasta renomeada ou apagada). Nada foi apagado na nuvem.',
          SituacaoRaiz.semMarcador => 'O arquivo de controle da pasta sumiu. Para não arriscar apagar nada, a sincronização desta pasta parou.',
          _ => 'Esta pasta pertence a outra sincronização. Para não arriscar apagar nada, a sincronização parou.',
        };
        _ev(Evento('pausado', par: c.id, detalhe: r.mensagem));
        continue;
      }
      ativos.add(c);
    }
    if (ativos.isEmpty) return res.values.toList();

    // Nuvem: árvore inicial ou mudanças (uma consulta para todos os pares).
    try {
      await _atualizarNuvem(ativos, res);
    } on ApiErro catch (e) {
      for (final c in ativos) {
        res[c.id]!
          ..estado = e.transitorio ? 'offline' : 'erro'
          ..mensagem = e.mensagem;
      }
      _salvarTodos(ativos);
      return res.values.toList();
    }

    for (final c in ativos) {
      final r = res[c.id]!;
      if (r.estado != 'ok') continue;
      final ultima = _ultimaVarredura[c.id];
      final d = _diarios[c.id]!;
      final pendente = d.baseAEnviar.isNotEmpty || d.baseARemover.isNotEmpty || d.juncaoSegura;
      if (ultima != null && !_sujos.contains(c.id) && !_nuvemMudou.contains(c.id) && !pendente &&
          DateTime.now().difference(ultima) < intervaloVarredura) {
        r.mensagem = 'nada mudou';
        continue;   // nada avisou, nada mudou na nuvem: não varre agora
      }
      _sujos.remove(c.id);
      _nuvemMudou.remove(c.id);
      try {
        await _cicloPar(c, r);
        if (r.estado == 'ok' && r.erros == 0 && r.pendentes == 0) _ultimaVarredura[c.id] = DateTime.now();
      } on ApiErro catch (e) {
        r.estado = e.desconectado ? 'erro' : (e.transitorio ? 'offline' : 'erro');
        r.mensagem = e.mensagem;
        r.erros++;
      } catch (e) {
        r.estado = 'erro';
        r.mensagem = 'Falha inesperada: $e';
        r.erros++;
      } finally {
        _salvar(c.id);
      }
    }
    await _replicar(ativos, res);
    return res.values.toList();
  }

  Future<Diario> _diario(ConfigPar c) async {
    final ja = _diarios[c.id];
    if (ja != null) return ja;
    var d = Diario.ler(_pastaPar(c.id), c.id);
    if (d == null) {
      // Diário perdido (ou primeira vez): JUNÇÃO SEGURA, com a base que o
      // servidor guardou (ajuda a reconhecer o que já estava igual).
      d = Diario(c.id)..juncaoSegura = true;
      try {
        var depois = 0;
        while (true) {
          final b = await api.baseDoPar(c.id, depois);
          for (final l in (b['itens'] as List).cast<Map<String, dynamic>>()) {
            final ib = ItemBase.deJson(l);
            d.base[ib.caminho] = ib;
          }
          depois = b['depois_de'] as int;
          if (b['mais'] != true) break;
        }
      } on ApiErro {
        // sem a base do servidor: compara impressões do zero
      }
    }
    _diarios[c.id] = d;
    return d;
  }

  void _salvar(int par) {
    final d = _diarios[par];
    if (d != null) d.gravar(_pastaPar(par));
  }

  void _salvarTodos(List<ConfigPar> l) {
    for (final c in l) {
      _salvar(c.id);
    }
  }

  /// Esquece o diário em memória (para reler do disco — testes e troca de conta).
  void esquecer() => _diarios.clear();

  // =====================================================================
  // Nuvem
  // =====================================================================

  Future<void> _atualizarNuvem(List<ConfigPar> ativos, Map<int, ResultadoPar> res) async {
    // Pares sem árvore completa: listagem paginada.
    for (final c in ativos) {
      final d = _diarios[c.id]!;
      if (!d.arvoreCompleta) await _listarArvore(c, d, res[c.id]!);
    }
    // Demais: mudanças, numa consulta só (repetida enquanto houver mais).
    var pedir = ativos.where((c) => _diarios[c.id]!.arvoreCompleta && res[c.id]!.estado == 'ok').toList();
    var voltas = 0;
    while (pedir.isNotEmpty && voltas++ < 50) {
      final resp = await api.mudancas([for (final c in pedir) {'par': c.id, 'cursor': _diarios[c.id]!.cursor}]);
      final continuar = <ConfigPar>[];
      for (final m in resp) {
        final c = pedir.firstWhere((x) => x.id == m['par'], orElse: () => pedir.first);
        if (c.id != m['par']) continue;
        final d = _diarios[c.id]!;
        final r = res[c.id]!;
        switch (m['estado']) {
          case 'ok':
            var listar = false;
            for (final mu in (m['mudancas'] as List).cast<Map<String, dynamic>>()) {
              if (mu['dentro'] == true && mu['item'] != null) {
                final it = ItemNuvem.deJson((mu['item'] as Map).cast<String, dynamic>());
                final antes = d.nuvem.itens[it.id];
                // Pasta que entrou (ou mudou de pai) traz filhos que o registro
                // não lista um a um: relista a árvore.
                if (it.tipo == Tipo.pasta && (antes == null || antes.pai != it.pai) &&
                    (mu['tipo'] == 'movido' || mu['tipo'] == 'restaurado')) {
                  listar = true;
                }
                d.nuvem.por(it);
              } else {
                d.nuvem.tirar(mu['item_id'] as int);
              }
            }
            if ((m['mudancas'] as List).isNotEmpty) _nuvemMudou.add(c.id);
            d.cursor = m['cursor'] as int;
            if (listar) {
              d.arvoreCompleta = false;
              d.arvoreDepoisDe = 0;
              await _listarArvore(c, d, r);
            } else if (m['mais'] == true) {
              continuar.add(c);
            }
          case 'ressincronizar':
            d.arvoreCompleta = false;
            d.arvoreDepoisDe = 0;
            await _listarArvore(c, d, r);
          default:
            r.estado = 'erro';
            r.mensagem = switch (m['estado']) {
              'lixeira' => 'A pasta da nuvem foi para a lixeira. Restaure-a no NN Cloud ou remova esta sincronização. Nada foi apagado no computador.',
              'sem_acesso' => 'Você perdeu o acesso à pasta da nuvem. Nada foi apagado no computador.',
              _ => 'A pasta da nuvem não existe mais. Nada foi apagado no computador.',
            };
            _ev(Evento('pausado', par: c.id, detalhe: r.mensagem));
        }
      }
      pedir = continuar;
    }
  }

  Future<void> _listarArvore(ConfigPar c, Diario d, ResultadoPar r) async {
    final nova = ArvoreNuvem();
    var depois = 0;
    int? cursor;
    while (true) {
      final a = await api.arvore(c.id, depois);
      if (a['estado'] != 'ok') {
        r.estado = 'erro';
        r.mensagem = 'A pasta da nuvem não está disponível (${a['estado']}). Nada foi apagado no computador.';
        return;
      }
      cursor ??= a['cursor'] as int?;
      for (final i in (a['itens'] as List).cast<Map<String, dynamic>>()) {
        nova.por(ItemNuvem.deJson(i));
      }
      depois = a['depois_de'] as int;
      if (a['mais'] != true) break;
    }
    d.nuvem
      ..limpar()
      ..itens.addAll(nova.itens);
    d.cursor = cursor ?? d.cursor;
    d.arvoreCompleta = true;
    _nuvemMudou.add(c.id);
    d.arvoreDepoisDe = 0;
  }

  // =====================================================================
  // Um par
  // =====================================================================

  Future<void> _cicloPar(ConfigPar c, ResultadoPar r) async {
    final d = _diarios[c.id]!;
    final v = Varredura(ignorados).varrer(c.raiz);
    // Download interrompido (energia, app fechado à força) deixa um temporário.
    // Os de mais de 1 hora não pertencem a ninguém: saem.
    for (final t in v.temporarios) {
      try {
        if (DateTime.now().difference(t.statSync().modified).inMinutes > 60) t.deleteSync();
      } on FileSystemException {
        // em uso: fica para a próxima
      }
    }
    for (final e in v.problemas.entries) {
      r.problemas.add('${e.key}: ${e.value}');
    }
    final nuvem = d.nuvem.porCaminho();
    String real(String rel) => p.join(c.raiz, (v.real[rel] ?? rel).replaceAll('/', Platform.pathSeparator));

    Future<String?> impressaoLocal(String rel) async {
      final li = v.itens[rel];
      if (li == null) return null;
      final cache = d.impressoes[rel];
      if (cache != null && cache.tamanho == li.tamanho && cache.mtimeMs == li.mtimeMs) return cache.hex;
      final imp = await Impressao.deArquivo(File(real(rel)));
      if (imp == null) return null;
      d.impressoes[rel] = ImpressaoCache(li.tamanho, li.mtimeMs, imp.hex);
      return imp.hex;
    }

    final podeEditar = true;   // o servidor recusa o que não puder; o estado da raiz vem nas mudanças
    var plano = await planejar(
      nuvem: nuvem,
      local: v.itens,
      base: d.base,
      impressaoLocal: impressaoLocal,
      juncaoSegura: d.juncaoSegura,
      podeEditar: podeEditar,
    );

    // ---------- Freio da exclusão em massa ----------
    final excl = plano.exclusoesNuvem + plano.exclusoesLocais;
    final arquivosBase = d.base.values.where((b) => b.tipo == Tipo.arquivo).length;
    final grande = excl > limiteExclusoes || (arquivosBase >= 8 && excl > arquivosBase * limiteFracao);
    final liberado = (confirmadas[c.id]?.isAfter(DateTime.now())) ?? false;
    if (grande && !liberado) {
      final ex = plano.acoes.where((a) => a is LixeiraNuvem || a is LixeiraLocal).map((a) => a.caminho).take(10).toList();
      r.exclusao = ExclusaoEmMassa(c.id, plano.exclusoesNuvem, plano.exclusoesLocais, excl, ex);
      r.estado = 'aguardando_confirmacao';
      r.mensagem = '$excl itens seriam apagados de uma vez. Confirme no aplicativo para continuar.';
      _ev(Evento('confirmar_exclusao', par: c.id, detalhe: r.mensagem));
      plano = Plano(plano.acoes.where((a) => a is! LixeiraNuvem && a is! LixeiraLocal).toList());
    }

    final ex = _Execucao(this, c, d, v, r, real);
    await ex.executar(plano);

    r.pendentes = r.problemas.length;
    if (r.erros == 0 && r.estado == 'ok') {
      d.juncaoSegura = false;   // um ciclo limpo: as exclusões voltam a valer
    }
  }

  // =====================================================================
  // Réplica no servidor
  // =====================================================================

  Future<void> _replicar(List<ConfigPar> ativos, Map<int, ResultadoPar> res) async {
    for (final c in ativos) {
      final d = _diarios[c.id]!;
      final r = res[c.id]!;
      try {
        final linhas = d.baseAEnviar.values.toList();
        final remover = d.baseARemover.toList();
        var i = 0, j = 0;
        while (i < linhas.length || j < remover.length || (i == 0 && j == 0)) {
          final lote = linhas.skip(i).take(900).map((b) => b.paraJson()).toList();
          final rem = remover.skip(j).take(1000 - lote.length).toList();
          await api.gravarBase(c.id, lote, rem, cursor: d.cursor);
          i += lote.length;
          j += rem.length;
          if (lote.isEmpty && rem.isEmpty) break;
        }
        d.baseAEnviar.clear();
        d.baseARemover.clear();
        final arqs = d.base.values.where((b) => b.tipo == Tipo.arquivo).toList();
        await api.atualizarPar(c.id, {
          'estado': r.estado == 'ok' || r.estado == 'aguardando_confirmacao' ? 'ativa' : 'erro',
          'erro': r.estado == 'ok' ? null : r.mensagem,
          'arquivos': arqs.length,
          'pastas': d.base.values.where((b) => b.tipo == Tipo.pasta).length,
          'bytes': arqs.fold<int>(0, (s, b) => s + (b.tamanho ?? 0)),
          'pendentes': r.pendentes,
          'erros': r.erros,
          if (r.estado == 'ok') 'sincronizado': 1,
        });
      } on ApiErro {
        // fica para o próximo ciclo (o diário guarda o que falta)
      }
      _salvar(c.id);
    }
    if (_historico.isNotEmpty) {
      try {
        while (_historico.isNotEmpty) {
          final lote = _historico.take(500).toList();
          await api.gravarHistorico(lote);
          _historico.removeRange(0, lote.length);
        }
      } on ApiErro {
        // reenvia no próximo ciclo (o servidor descarta repetidos pelo cliente_id)
      }
    }
  }

  void historico(int par, String acao, String caminho, {int? itemId, int? tamanho, String? detalhe}) {
    _historico.add({
      'cliente_id': _uuid(),
      'par': par,
      'acao': acao,
      'caminho': caminho,
      'item_id': itemId,
      'tamanho': tamanho,
      'detalhe': detalhe,
      'ocorrido_em': DateTime.now().millisecondsSinceEpoch,
    });
    if (_historico.length > 5000) _historico.removeRange(0, _historico.length - 5000);
  }

  String _uuid() {
    final b = List<int>.generate(16, (_) => _rnd.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  /// Apaga da lixeira local o que passou de `dias` (chamar uma vez por dia).
  static int limparLixeiraLocal(String raiz, int dias) {
    final l = Directory(p.join(raiz, pastaLixeiraLocal));
    if (!l.existsSync()) return 0;
    final limite = DateTime.now().subtract(Duration(days: dias));
    var n = 0;
    for (final e in l.listSync(followLinks: false)) {
      if (e is Directory && e.statSync().modified.isBefore(limite)) {
        e.deleteSync(recursive: true);
        n++;
      }
    }
    return n;
  }
}

// =========================================================================
// Execução de um plano
// =========================================================================

class _Execucao {
  final Sincronizador s;
  final ConfigPar c;
  final Diario d;
  final ResultadoVarredura v;
  final ResultadoPar r;
  final String Function(String) real;
  late final String lote = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;

  _Execucao(this.s, this.c, this.d, this.v, this.r, this.real);

  Api get api => s.api;

  Future<void> executar(Plano plano) async {
    // Grupos pela ordem; transferências do mesmo grupo em paralelo (até 3).
    final grupos = <int, List<Acao>>{};
    for (final a in plano.acoes) {
      grupos.putIfAbsent(a.ordem, () => []).add(a);
    }
    for (final o in grupos.keys.toList()..sort()) {
      final acoes = grupos[o]!;
      if (o == 3) {
        await _pool(acoes);
      } else if (o == 4) {
        await _lixeiras(acoes);
      } else {
        for (final a in acoes) {
          await _uma(a);
        }
      }
    }
  }

  Future<void> _pool(List<Acao> acoes) async {
    final fila = List<Acao>.of(acoes);
    Future<void> trabalhador() async {
      while (fila.isNotEmpty) {
        await _uma(fila.removeAt(0));
      }
    }

    await Future.wait(List.generate(s.paralelo, (_) => trabalhador()));
  }

  Future<void> _uma(Acao a) async {
    try {
      switch (a) {
        case MoverLocal():
          await _moverLocal(a);
        case MoverNuvem():
          await _moverNuvem(a);
        case CriarPastaLocal():
          Directory(_abs(a.caminho)).createSync(recursive: true);
          d.porBase(ItemBase(caminho: a.caminho, itemId: a.itemId, tipo: Tipo.pasta));
        case CriarPastaNuvem():
          final id = await _pastaNuvem(a.caminho);
          if (id != null) d.porBase(ItemBase(caminho: a.caminho, itemId: id, tipo: Tipo.pasta));
          s.historico(c.id, 'pasta_criada', a.caminho, itemId: id);
        case EnviarNovo():
          await _enviar(a.caminho, null, null);
        case EnviarAtualizacao():
          await _enviar(a.caminho, a.itemId, a.baseVersao);
        case Baixar():
          await _baixar(a.caminho, a.item, a.esperado);
        case Conflito():
          await _conflito(a.caminho, a.item);
        case SoBase():
          d.porBase(a.base);
        case RemoverBase():
          d.tirarBase(a.caminho);
        case Problema():
          r.problemas.add('${a.caminho}: ${a.motivo}');
        case LixeiraNuvem():
        case LixeiraLocal():
          break;   // feitos em lote
      }
    } on ApiErro catch (e) {
      if (e.transitorio || e.desconectado) rethrow;
      r.erros++;
      r.problemas.add('${a.caminho}: ${e.mensagem}');
      s.historico(c.id, 'erro', a.caminho, detalhe: e.mensagem);
      s._ev(Evento('erro', par: c.id, caminho: a.caminho, detalhe: e.mensagem));
    } on FileSystemException catch (e) {
      r.erros++;
      final m = e.osError?.message ?? e.message;
      r.problemas.add('${a.caminho}: $m');
      s.historico(c.id, 'erro', a.caminho, detalhe: m);
    }
  }

  // ---------- caminhos ----------

  String _abs(String rel) => v.real.containsKey(rel) ? real(rel) : p.join(c.raiz, rel.replaceAll('/', Platform.pathSeparator));

  /// Id da pasta da nuvem de um caminho relativo ('' = raiz do par), criando o que faltar.
  Future<int?> _pastaNuvem(String rel) async {
    if (rel.isEmpty) return c.raizId;
    final ja = d.nuvem.porCaminho()[rel];
    if (ja != null && ja.tipo == Tipo.pasta) return ja.id;
    final k = chaveCaminho(rel);
    for (final e in d.nuvem.porCaminho().entries) {
      if (e.value.tipo == Tipo.pasta && chaveCaminho(e.key) == k) return e.value.id;
    }
    final g = await api.garantir(espacoId: c.espacoId, pastaId: c.raizId, caminhos: [rel]);
    final mapa = _mapa(g['pastas']);
    final erros = _mapa(g['erros']);
    if (erros.isNotEmpty) throw ApiErro(422, erros.values.first.toString());
    // Registra a cadeia na árvore local (para os próximos caminhos acharem).
    final partes = rel.split('/');
    int? pai;
    for (var i = 0; i < partes.length; i++) {
      final sub = partes.sublist(0, i + 1).join('/');
      final id = mapa[sub] as int?;
      if (id == null) continue;
      if (!d.nuvem.itens.containsKey(id)) {
        d.nuvem.por(ItemNuvem(id: id, pai: pai, tipo: Tipo.pasta, nome: partes[i]));
      }
      pai = id;
    }
    return mapa[rel] as int? ?? pai;
  }

  ItemNuvem _daResposta(Map<String, dynamic> j) {
    final it = ItemNuvem.deJson(j);
    if (it.pai != null && it.pai == c.raizId) it.pai = null;   // o pai é relativo à raiz do par
    return it;
  }

  // ---------- envio ----------

  Future<void> _enviar(String rel, int? itemId, int? baseVersao) async {
    final f = File(_abs(rel));
    final st1 = f.statSync();
    if (st1.type != FileSystemEntityType.file) return;
    final imp = await Impressao.deArquivo(f);
    final st2 = f.statSync();
    if (imp == null || st2.size != st1.size || st2.modified != st1.modified) {
      r.pendentes++;   // está sendo gravado agora: fica para o próximo ciclo
      return;
    }
    d.impressoes[rel] = ImpressaoCache(st2.size, st2.modified.millisecondsSinceEpoch, imp.hex);
    final corpo = <String, dynamic>{
      'nome': nomeDe(rel),
      'tamanho': imp.tamanho,
      'impressao': imp.hex,
      'partes': imp.partes,
      'mtime_ms': st2.modified.millisecondsSinceEpoch,
      'mime': 'application/octet-stream',
    };
    if (itemId != null) {
      corpo['item_id'] = itemId;
      corpo['base_versao'] = baseVersao;
    } else {
      final paiRel = paiDe(rel);
      final paiId = await _pastaNuvem(paiRel);
      if (paiId == null) {
        corpo['espaco_id'] = c.espacoId;
      } else {
        corpo['pasta_id'] = paiId;
      }
    }
    var ini = await api.iniciarEnvio(corpo);
    Map<String, dynamic> fim;
    if (ini['reaproveitado'] == true) {
      fim = {'item': ini['item'], 'evento': ini['evento']};
    } else {
      final envio = ini['envio'] as String;
      var urls = (ini['partes'] as List).cast<Map<String, dynamic>>();
      final n = ini['n_partes'] as int;
      final feitas = <int>{};
      var tentativas = 0;
      while (feitas.length < n) {
        if (urls.length < n - feitas.length || urls.isEmpty) {
          final e = await api.estadoEnvio(envio, de: 1);
          feitas.addAll(((e['recebidas'] as List?) ?? []).cast<int>());
          urls = ((e['partes'] as List?) ?? []).cast<Map<String, dynamic>>();
          if (urls.isEmpty && feitas.length < n) throw const ApiErro(0, 'O servidor não devolveu os endereços de envio.');
        }
        var falhou = false;
        for (final u in urls) {
          final num = u['n'] as int;
          if (feitas.contains(num)) continue;
          final inicio = u['inicio'] as int, tam = u['tamanho'] as int;
          final code = await api.putParte(u['url'] as String, _mapa(u['cabecalhos']).map((k, v) => MapEntry(k, '$v')),
              f.openRead(inicio, inicio + tam), tam);
          if (code == 200) {
            feitas.add(num);
            s._ev(Evento('progresso', par: c.id, caminho: rel, tamanho: tam));
          } else {
            falhou = true;
            if (code == 400 || code == 403) break;   // URL vencida ou arquivo mudou: pede de novo
          }
        }
        if (falhou) {
          if (++tentativas > 6) throw const ApiErro(0, 'O envio direto ao armazenamento falhou várias vezes.');
          await Future<void>.delayed(Duration(seconds: 1 << (tentativas - 1)));
          urls = [];
        }
      }
      // Arquivo mudou enquanto subia? Então não conclui com conteúdo misturado.
      final st3 = f.statSync();
      if (st3.size != st2.size || st3.modified != st2.modified) {
        await api.cancelarEnvio(envio);
        r.pendentes++;
        return;
      }
      try {
        fim = await api.concluirEnvio(envio);
      } on ApiErro catch (e) {
        if (e.status != 409) rethrow;
        ini = await api.estadoEnvio(envio);
        fim = await api.concluirEnvio(envio);
      }
    }
    final item = _daResposta((fim['item'] as Map).cast<String, dynamic>());
    d.nuvem.por(item);
    var destino = rel;
    if (fim['evento'] == 'conflito') {
      // A nuvem mudou enquanto subia: o que subiu virou a cópia de conflito.
      // O arquivo local passa a ter o nome dela; o original desce no próximo ciclo.
      final caminho = d.nuvem.caminhoDe(item.id) ?? (paiDe(rel).isEmpty ? item.nome : '${paiDe(rel)}/${item.nome}');
      File(_abs(rel)).renameSync(p.join(c.raiz, caminho.replaceAll('/', Platform.pathSeparator)));
      destino = caminho;
      r.conflitos++;
      s.historico(c.id, 'conflito', caminho, itemId: item.id, tamanho: imp.tamanho);
      s._ev(Evento('conflito', par: c.id, caminho: caminho));
    }
    final stf = File(_abs(destino) == _abs(rel) ? _abs(rel) : p.join(c.raiz, destino.replaceAll('/', Platform.pathSeparator))).statSync();
    d.porBase(ItemBase(caminho: destino, itemId: item.id, tipo: Tipo.arquivo, tamanho: stf.size,
        mtimeMs: stf.modified.millisecondsSinceEpoch, impressao: imp.hex, versao: item.versao));
    r.enviados++;
    if (fim['evento'] != 'conflito') {
      s.historico(c.id, itemId == null ? 'enviado' : 'atualizado', destino, itemId: item.id, tamanho: imp.tamanho);
      s._ev(Evento('enviado', par: c.id, caminho: destino, tamanho: imp.tamanho));
    }
  }

  // ---------- download ----------

  Future<void> _baixar(String rel, ItemNuvem item, ItemBase? esperado) async {
    final alvo = File(_abs(rel));
    // ⚠️ Reconfere o arquivo local ANTES de substituir: se mudou depois da
    // varredura (ou apareceu), segue o caminho do conflito.
    if (alvo.existsSync()) {
      final st = alvo.statSync();
      final igual = esperado != null && st.size == esperado.tamanho && st.modified.millisecondsSinceEpoch == esperado.mtimeMs;
      if (!igual) {
        await _conflito(rel, item);
        return;
      }
    }
    alvo.parent.createSync(recursive: true);
    final b = await api.baixar(item.id);
    final tmp = File(p.join(alvo.parent.path, '$prefixoTemporario${DateTime.now().microsecondsSinceEpoch}'));
    if (b['url'] == null) {
      tmp.writeAsBytesSync(const []);
    } else {
      var tentativas = 0;
      while (true) {
        final sink = tmp.openWrite();
        final code = await api.baixarPara(b['url'] as String, sink, aoReceber: (n) => s._ev(Evento('progresso', par: c.id, caminho: rel, tamanho: n)));
        await sink.close();
        if (code == 200) break;
        if (++tentativas > 5) {
          if (tmp.existsSync()) tmp.deleteSync();
          throw ApiErro(0, 'O download falhou (código $code).');
        }
        await Future<void>.delayed(Duration(seconds: 1 << (tentativas - 1)));
      }
    }
    final imp = await Impressao.deArquivo(tmp);
    if (imp == null || (item.impressao != null && imp.hex != item.impressao) || imp.tamanho != (b['tamanho'] as int? ?? imp.tamanho)) {
      tmp.deleteSync();
      throw const ApiErro(422, 'O arquivo baixado não confere com a nuvem (vai tentar de novo).');
    }
    if (item.mtimeMs != null) {
      tmp.setLastModifiedSync(DateTime.fromMillisecondsSinceEpoch(item.mtimeMs!));
    }
    if (alvo.existsSync()) _paraLixeira(rel, alvo);   // a versão anterior fica guardada
    tmp.renameSync(alvo.path);
    final st = alvo.statSync();
    d.impressoes[rel] = ImpressaoCache(st.size, st.modified.millisecondsSinceEpoch, imp.hex);
    d.porBase(ItemBase(caminho: rel, itemId: item.id, tipo: Tipo.arquivo, tamanho: st.size, mtimeMs: st.modified.millisecondsSinceEpoch,
        impressao: imp.hex, versao: item.versao));
    r.baixados++;
    s.historico(c.id, esperado == null ? 'baixado' : 'atualizado', rel, itemId: item.id, tamanho: st.size);
    s._ev(Evento('baixado', par: c.id, caminho: rel, tamanho: st.size));
  }

  /// Os dois lados mudaram: a versão do PC vira "nome (conflito de PC data)"
  /// (sobe como arquivo novo) e a da nuvem fica com o nome.
  Future<void> _conflito(String rel, ItemNuvem item) async {
    final f = File(_abs(rel));
    if (f.existsSync()) {
      var nome = nomeConflito(nomeDe(rel), s.computador, DateTime.now());
      var n = 2;
      String caminho() => paiDe(rel).isEmpty ? nome : '${paiDe(rel)}/$nome';
      while (File(p.join(c.raiz, caminho().replaceAll('/', Platform.pathSeparator))).existsSync()) {
        nome = nomeComSufixo(nomeConflito(nomeDe(rel), s.computador, DateTime.now()), n++);
      }
      final novo = caminho();
      f.renameSync(p.join(c.raiz, novo.replaceAll('/', Platform.pathSeparator)));
      v.real.remove(rel);
      r.conflitos++;
      s.historico(c.id, 'conflito', novo, detalhe: 'versão deste computador guardada com outro nome');
      s._ev(Evento('conflito', par: c.id, caminho: novo));
      await _enviar(novo, null, null);
    }
    await _baixar(rel, item, null);
  }

  // ---------- movimentos ----------

  Future<void> _moverLocal(MoverLocal a) async {
    final de = _abs(a.de);
    final para = p.join(c.raiz, a.para.replaceAll('/', Platform.pathSeparator));
    Directory(p.dirname(para)).createSync(recursive: true);
    final ent = a.tipo == Tipo.pasta ? Directory(de) as FileSystemEntity : File(de);
    if (chaveCaminho(a.de) == chaveCaminho(a.para)) {
      // Só a caixa mudou: num disco que ignora caixa, passa por um nome temporário.
      final tmp = '$de$prefixoTemporario${DateTime.now().microsecondsSinceEpoch}';
      ent.renameSync(tmp);
      (a.tipo == Tipo.pasta ? Directory(tmp) as FileSystemEntity : File(tmp)).renameSync(para);
    } else {
      ent.renameSync(para);
    }
    d.moverBase(a.de, a.para);
    s.historico(c.id, a.tipo == Tipo.pasta || paiDe(a.de) != paiDe(a.para) ? 'movido' : 'renomeado', a.para, itemId: a.itemId,
        detalhe: 'de ${a.de}');
  }

  Future<void> _moverNuvem(MoverNuvem a) async {
    Map<String, dynamic>? res;
    if (chaveCaminho(paiDe(a.de)) != chaveCaminho(paiDe(a.para))) {
      final destino = await _pastaNuvem(paiDe(a.para));
      res = await api.mover(a.itemId, espacoId: destino == null ? c.espacoId : null, pastaId: destino);
    }
    if (nomeDe(a.de) != nomeDe(a.para)) {
      res = await api.renomear(a.itemId, nomeDe(a.para));
    }
    if (res != null) d.nuvem.por(_daResposta(res));
    d.moverBase(a.de, a.para);
    s.historico(c.id, paiDe(a.de) != paiDe(a.para) ? 'movido' : 'renomeado', a.para, itemId: a.itemId, detalhe: 'de ${a.de}');
  }

  // ---------- lixeiras ----------

  Future<void> _lixeiras(List<Acao> acoes) async {
    final nuvem = acoes.whereType<LixeiraNuvem>().toList();
    final liberado = (s.confirmadas[c.id]?.isAfter(DateTime.now())) ?? false;
    for (var i = 0; i < nuvem.length; i += 200) {
      final lote = nuvem.skip(i).take(200).toList();
      List<Map<String, dynamic>> res;
      try {
        res = await api.lixeira(lote.map((a) => a.itemId).toList(), confirmado: liberado);
      } on ApiErro catch (e) {
        if (e.status == 428) {
          r.estado = 'aguardando_confirmacao';
          r.mensagem = e.mensagem;
          s._ev(Evento('confirmar_exclusao', par: c.id, detalhe: e.mensagem));
          break;
        }
        rethrow;
      }
      for (final x in res) {
        final a = lote.firstWhere((l) => l.itemId == x['id']);
        if (x['ok'] == true) {
          d.nuvem.tirar(a.itemId);
          d.tirarBase(a.caminho, comFilhos: a.tipo == Tipo.pasta);
          r.excluidos++;
          s.historico(c.id, 'excluido_local', a.caminho, itemId: a.itemId, detalhe: 'apagado no computador — enviado para a lixeira da nuvem');
        } else {
          r.problemas.add('${a.caminho}: ${x['erro']}');
        }
      }
    }
    for (final a in acoes.whereType<LixeiraLocal>()) {
      final abs = _abs(a.caminho);
      if (a.tipo == Tipo.arquivo) {
        final f = File(abs);
        if (!f.existsSync()) {
          d.tirarBase(a.caminho);
          continue;
        }
        final st = f.statSync();
        final e = a.esperado;
        if (e != null && (st.size != e.tamanho || st.modified.millisecondsSinceEpoch != e.mtimeMs)) continue;   // mudou: sobe no próximo ciclo
        _paraLixeira(a.caminho, f);
      } else {
        final dir = Directory(abs);
        if (dir.existsSync()) _paraLixeira(a.caminho, dir);
      }
      d.tirarBase(a.caminho, comFilhos: a.tipo == Tipo.pasta);
      r.excluidos++;
      s.historico(c.id, 'excluido_nuvem', a.caminho, detalhe: 'apagado na nuvem — guardado na lixeira do aplicativo');
    }
  }

  /// Move para `<raiz>/.nncloud-lixeira/<data>/<caminho>` (mesmo disco: é um rename).
  void _paraLixeira(String rel, FileSystemEntity e) {
    final destino = p.join(c.raiz, pastaLixeiraLocal, lote, rel.replaceAll('/', Platform.pathSeparator));
    Directory(p.dirname(destino)).createSync(recursive: true);
    var alvo = destino;
    var n = 2;
    while (FileSystemEntity.typeSync(alvo, followLinks: false) != FileSystemEntityType.notFound) {
      alvo = '$destino ($n)';
      n++;
    }
    e.renameSync(alvo);
  }
}
