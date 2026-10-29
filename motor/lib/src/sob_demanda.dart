// "NN Cloud" SOB DEMANDA no Windows (Cloud Files API): o cérebro, em Dart puro.
//
// O Explorer mostra a pasta `%USERPROFILE%\NN Cloud` com Meu Drive, Compartilhados
// comigo e Drives compartilhados. Cada arquivo é um PLACEHOLDER: aparece com nome,
// tamanho e data, e só desce quando alguém o abre (o Windows chama o app, que baixa
// e entrega os bytes). O que entra na pasta sobe; "Liberar espaço" é do Explorer.
//
//   nuvem → disco ... `sincronizar()`: árvore inteira na primeira vez (e ao abrir o
//                     app), depois só as mudanças (`fp/mudancas`, âncora no servidor)
//   disco → nuvem ... `localMudou()` (observador de pasta) e as respostas a
//                     `aoApagar` / `aoRenomear` (o Windows PERGUNTA antes de apagar
//                     ou renomear um placeholder — dá para recusar)
//   abrir ........... `baixar()`: download conferido pela impressão
//
// ⚠️ O que mexe no disco passa pela interface [NativoNuvem]: no Windows é a Cloud
// Files API (C++ no runner); nos testes, um simulador. Assim a regra inteira é
// testada sem Windows.
// ⚠️ A IDENTIDADE de cada placeholder é "<id>" (pastas) ou "<id>:<versão>"
// (arquivos): é por ela que se sabe de qual versão uma edição local partiu — a
// base do conflito.
// ⚠️ Nada aqui lê o CONTEÚDO de um placeholder que pode não estar no disco: ler
// faria o Windows pedir o download ao próprio app (o nativo recusa esse caso).
// Só se lê arquivo que não é placeholder ou que foi editado (fora de "em dia").
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'api.dart';
import 'ignorados.dart';
import 'impressao.dart';
import 'nomes.dart';
import 'transferencia.dart';

/// Um item do domínio (`/v1/cloud/fp/*`).
class ItemFp {
  final String id;
  final String? pai;
  final String nome;
  final bool pasta;
  final int tamanho;
  final String? impressao;
  final int versao;
  final int criadoMs, modificadoMs;

  const ItemFp(this.id, this.pai, this.nome, this.pasta,
      {this.tamanho = 0, this.impressao, this.versao = 0, this.criadoMs = 0, this.modificadoMs = 0});

  factory ItemFp.deJson(Map j) => ItemFp(
        '${j['id']}',
        j['pai'] as String?,
        '${j['nome']}',
        j['tipo'] == 'pasta',
        tamanho: (j['tamanho'] as num?)?.toInt() ?? 0,
        impressao: j['impressao'] as String?,
        versao: (j['versao'] as num?)?.toInt() ?? 0,
        criadoMs: (j['criado_ms'] as num?)?.toInt() ?? 0,
        modificadoMs: (j['modificado_ms'] as num?)?.toInt() ?? 0,
      );

  String get identidade => pasta ? id : '$id:$versao';
}

String idDaIdentidade(String? identidade) => identidade == null ? '' : identidade.split(':').first;

int? versaoDaIdentidade(String? identidade) {
  final i = identidade?.indexOf(':') ?? -1;
  return i < 0 ? null : int.tryParse(identidade!.substring(i + 1));
}

int? numeroDoItem(String id) => id.startsWith('i') ? int.tryParse(id.substring(1)) : null;

/// Como o sistema vê um caminho do disco.
class EstadoLocal {
  final bool placeholder;   // é um arquivo/pasta da nuvem (tem identidade)
  final bool emDia;         // igual à nuvem (não foi editado aqui)
  final bool pasta;
  final bool hidratado;     // o conteúdo está no disco
  final String? identidade;
  const EstadoLocal({this.placeholder = false, this.emDia = false, this.pasta = false, this.hidratado = true, this.identidade});
}

class NovoPlaceholder {
  final String nome, identidade;
  final bool pasta;
  final int tamanho, criadoMs, modificadoMs;
  const NovoPlaceholder(this.nome, this.identidade, this.pasta, this.tamanho, this.criadoMs, this.modificadoMs);
}

/// Um caminho do disco que NÃO está "placeholder em dia" (ver [NativoNuvem.varrer]).
class EntradaLocal {
  final String caminho;
  final bool pasta, placeholder, emDia;
  const EntradaLocal(this.caminho, {this.pasta = false, this.placeholder = false, this.emDia = false});
}

/// O que o sistema operacional faz por nós (Cloud Files API no Windows).
abstract class NativoNuvem {
  /// Percorre a árvore inteira abaixo de [raiz] e devolve só o que está FORA de
  /// "placeholder em dia": arquivo/pasta comum (nunca subiu), arquivo editado e
  /// pasta da nuvem que perdeu a marca de "em dia" porque algo mudou dentro.
  Future<List<EntradaLocal>> varrer(String raiz);

  /// Marca uma pasta da nuvem (ou a raiz) como "em dia" de novo.
  Future<bool> marcarEmDia(String caminho);

  /// Cria placeholders (só nuvem, em dia) dentro de [pasta]. Nome que já existe é ignorado.
  Future<void> criarPlaceholders(String pasta, List<NovoPlaceholder> itens);

  /// null = o caminho não existe.
  Future<EstadoLocal?> estado(String caminho);

  /// Troca a identidade/metadados de um placeholder e o marca em dia. [desidratar]:
  /// tira o conteúdo do disco (a versão da nuvem mudou ou "liberar depois de enviar").
  Future<bool> atualizar(String caminho, String identidade,
      {int? tamanho, int? criadoMs, int? modificadoMs, bool desidratar = false});

  /// Transforma um arquivo/pasta comum (que acabou de subir) em placeholder em dia.
  Future<bool> converter(String caminho, String identidade, {bool desidratar = false});

  Future<bool> desidratar(String caminho);

  /// Renomear/mover/apagar no disco a pedido da NUVEM (o nativo não pergunta à nuvem
  /// de volta quando quem mexe é o próprio app).
  Future<void> mover(String de, String para);
  Future<void> apagar(String caminho);
}

/// Algo a mostrar na tela do app (histórico/problemas).
class EventoSobDemanda {
  final String tipo;        // enviado | baixado | conflito | removido | problema
  final String caminho;
  final String? detalhe;
  const EventoSobDemanda(this.tipo, this.caminho, [this.detalhe]);
  @override
  String toString() => '$tipo $caminho${detalhe == null ? '' : ' ($detalhe)'}';
}

class ProvedorSobDemanda {
  final Api api;
  final NativoNuvem nativo;
  final String raiz;
  final File arquivoEstado;
  final Ignorados ignorados;
  final String computador;
  bool liberarAposEnviar;
  final void Function(EventoSobDemanda e)? aoEvento;

  /// Tempo que um arquivo precisa ficar parado antes de subir (ainda pode estar sendo gravado).
  Duration esperaGravacao;

  String? ancora;
  /// id do domínio → caminho relativo ('/' como separador; '' = a raiz).
  final Map<String, String> indice = {};
  bool _completoPendente = false;
  int? _meuDrive;
  Future<void> _fila = Future.value();
  final Set<String> _sujos = {};
  Timer? _timerSujos;
  /// O que deu problema DEFINITIVO ao subir (sem permissão, fora de Meu Drive…):
  /// caminho → como ele estava. A conferência do disco não tenta de novo enquanto
  /// ele não mudar — senão o mesmo aviso voltaria a cada ciclo.
  final Map<String, String> _recusados = {};

  ProvedorSobDemanda({
    required this.api,
    required this.nativo,
    required this.raiz,
    required this.arquivoEstado,
    required this.computador,
    Ignorados? ignorados,
    this.liberarAposEnviar = false,
    this.aoEvento,
    this.esperaGravacao = const Duration(seconds: 2),
  }) : ignorados = ignorados ?? Ignorados();

  // ===================================================================
  // Estado (âncora + índice)
  // ===================================================================

  void carregar() {
    try {
      final j = jsonDecode(arquivoEstado.readAsStringSync()) as Map<String, dynamic>;
      ancora = j['ancora'] as String?;
      indice
        ..clear()
        ..addAll(((j['indice'] as Map?) ?? {}).map((k, v) => MapEntry('$k', '$v')));
    } catch (_) {
      ancora = null;
      indice.clear();
    }
  }

  void _salvar() {
    try {
      arquivoEstado.parent.createSync(recursive: true);
      final tmp = File('${arquivoEstado.path}.tmp');
      tmp.writeAsStringSync(jsonEncode({'ancora': ancora, 'indice': indice}));
      tmp.renameSync(arquivoEstado.path);
    } catch (_) {}
  }

  /// Esquece tudo (desligar): a próxima vez começa pela árvore inteira.
  void esquecer() {
    ancora = null;
    indice.clear();
    try {
      if (arquivoEstado.existsSync()) arquivoEstado.deleteSync();
    } catch (_) {}
  }

  // ===================================================================
  // Fila: uma coisa de cada vez (árvore, mudanças, envios)
  // ===================================================================

  Future<T> _serial<T>(Future<T> Function() f) {
    final c = Completer<T>();
    _fila = _fila.then((_) async {
      try {
        c.complete(await f());
      } catch (e, s) {
        c.completeError(e, s);
      }
    });
    return c.future;
  }

  // ===================================================================
  // Caminhos
  // ===================================================================

  String _abs(String rel) => rel.isEmpty ? raiz : p.join(raiz, rel.split('/').join(p.separator));

  /// null = fora da raiz.
  String? relDe(String abs) {
    final n = p.normalize(abs);
    if (p.equals(n, raiz)) return '';
    if (!p.isWithin(raiz, n)) return null;
    return p.relative(n, from: raiz).split(p.separator).join('/');
  }

  static String _junta(String rel, String nome) => rel.isEmpty ? nome : '$rel/$nome';
  static String _paiDe(String rel) => rel.contains('/') ? rel.substring(0, rel.lastIndexOf('/')) : '';
  static String _nomeDe(String rel) => rel.contains('/') ? rel.substring(rel.lastIndexOf('/') + 1) : rel;

  void _ev(String tipo, String caminho, [String? detalhe]) => aoEvento?.call(EventoSobDemanda(tipo, caminho, detalhe));

  void _moverIndice(String de, String para) {
    final novos = <String, String>{};
    indice.forEach((id, rel) {
      if (rel == de) {
        novos[id] = para;
      } else if (rel.startsWith('$de/')) {
        novos[id] = para + rel.substring(de.length);
      }
    });
    indice.addAll(novos);
  }

  void _tirarDoIndice(String rel) => indice.removeWhere((_, r) => r == rel || r.startsWith('$rel/'));

  // ===================================================================
  // Destino de uma escrita
  // ===================================================================

  Future<int> _meuDriveId() async {
    if (_meuDrive != null) return _meuDrive!;
    final eu = await api.eu();
    return _meuDrive = ((eu['meu_drive'] as Map)['id'] as num).toInt();
  }

  /// O destino (para `envios` e `pastas`) de quem é criado dentro do contêiner [id].
  Future<Map<String, dynamic>?> _destino(String id) async {
    if (id == 'meu') return {'espaco_id': await _meuDriveId()};
    if (id.startsWith('e')) {
      final n = int.tryParse(id.substring(1));
      return n == null ? null : {'espaco_id': n};
    }
    final n = numeroDoItem(id);
    return n == null ? null : {'pasta_id': n};
  }

  /// O contêiner (id do domínio) da pasta relativa [rel]. null = não é da nuvem (ainda).
  Future<String?> _idDaPasta(String rel) async {
    if (rel.isEmpty) return 'raiz';
    final est = await nativo.estado(_abs(rel));
    if (est == null || !est.placeholder || !est.pasta) return null;
    return idDaIdentidade(est.identidade);
  }

  // ===================================================================
  // nuvem → disco
  // ===================================================================

  /// Põe o disco igual à nuvem: a árvore inteira na primeira vez, depois só as mudanças.
  Future<void> sincronizar({bool completo = false}) => _serial(() async {
        if (completo || ancora == null || _completoPendente) {
          await _completo();
        } else {
          await _mudancas();
        }
      });

  Future<void> _completo() async {
    final a = await api.fpAncora();   // ANTES de percorrer: o que mudar durante a volta vem depois
    _completoPendente = false;
    indice
      ..clear()
      ..['raiz'] = '';
    await _popular('raiz', '');
    ancora = a;
    _salvar();
  }

  Future<List<ItemFp>> _filhos(String id) async {
    final out = <ItemFp>[];
    int? pos = 0;
    while (pos != null) {
      final r = await api.fpFilhos(id, pos);
      out.addAll(((r['itens'] as List?) ?? const []).map((j) => ItemFp.deJson(j as Map)));
      pos = (r['proximo'] as num?)?.toInt();
    }
    return out;
  }

  NovoPlaceholder _np(ItemFp f) => NovoPlaceholder(f.nome, f.identidade, f.pasta, f.tamanho, f.criadoMs, f.modificadoMs);

  /// Uma pasta da nuvem e tudo abaixo dela (a população é COMPLETA: o Explorer não pergunta).
  Future<void> _popular(String id, String rel) async {
    final filhos = await _filhos(id);
    final chaves = {for (final f in filhos) chaveNome(f.nome)};
    final novos = <NovoPlaceholder>[];
    final aEnviar = <String>[];
    for (final f in filhos) {
      final fr = _junta(rel, f.nome);
      indice[f.id] = fr;
      final est = await nativo.estado(_abs(fr));
      if (est == null) {
        novos.add(_np(f));
      } else if (est.placeholder && idDaIdentidade(est.identidade) == f.id) {
        if (!f.pasta) await _conferirArquivo(fr, f, est);
      } else if (est.placeholder) {
        // Placeholder de OUTRO item com este nome (apagado e recriado na nuvem).
        if (est.emDia && await _apagarLocal(fr)) novos.add(_np(f));
      } else if (est.pasta && f.pasta) {
        // Pasta comum com o nome de uma pasta da nuvem: viram a mesma (o conteúdo se acerta abaixo).
        await nativo.converter(_abs(fr), f.identidade);
      } else {
        // Arquivo deste computador com o nome de um item da nuvem: o local vira a cópia de conflito.
        final livre = _nomeLivre(rel, nomeConflito(f.nome, computador, DateTime.now()));
        await nativo.mover(_abs(fr), _abs(_junta(rel, livre)));
        aEnviar.add(_junta(rel, livre));
        novos.add(_np(f));
        _ev('conflito', _junta(rel, livre), 'a versão deste computador foi guardada com outro nome');
      }
    }
    if (novos.isNotEmpty) await nativo.criarPlaceholders(_abs(rel), novos);
    // O que está no disco e a nuvem não tem.
    final dir = Directory(_abs(rel));
    if (dir.existsSync()) {
      for (final e in dir.listSync(followLinks: false)) {
        final nome = p.basename(e.path);
        if (ignorados.nome(nome) || chaves.contains(chaveNome(nome))) continue;
        final er = _junta(rel, nome);
        final est = await nativo.estado(e.path);
        if (est == null) continue;
        if (est.placeholder && (est.emDia || est.pasta)) {
          // Saiu da nuvem. Pasta: some o que está em dia; o que foi editado aqui fica.
          if (await _apagarLocal(er)) _ev('removido', er);
        } else {
          aEnviar.add(er);
        }
      }
    }
    for (final r in aEnviar) {
      await _enviarLocal(r);
    }
    for (final f in filhos.where((f) => f.pasta)) {
      final fr = indice[f.id];
      if (fr != null) await _popular(f.id, fr);
    }
  }

  String _nomeLivre(String rel, String nome) {
    var n = nome, i = 2;
    while (FileSystemEntity.typeSync(_abs(_junta(rel, n)), followLinks: false) != FileSystemEntityType.notFound) {
      n = nomeComSufixo(nome, i++);
    }
    return n;
  }

  /// Um arquivo que existe dos dois lados: a nuvem mudou?
  Future<void> _conferirArquivo(String rel, ItemFp f, EstadoLocal est) async {
    final v = versaoDaIdentidade(est.identidade);
    if (v == f.versao) {
      if (!est.emDia) await _enviarLocal(rel);   // editado aqui com o app fechado
      return;
    }
    if (est.emDia) {
      // Versão nova na nuvem: o conteúdo antigo sai do disco (desce de novo quando abrirem).
      await nativo.atualizar(_abs(rel), f.identidade,
          tamanho: f.tamanho, criadoMs: f.criadoMs, modificadoMs: f.modificadoMs, desidratar: true);
    } else {
      // Os dois lados mudaram: a versão daqui sobe com a base antiga e o servidor
      // guarda como cópia de conflito.
      await _enviarLocal(rel);
    }
  }

  Future<void> _mudancas() async {
    var mais = true;
    while (mais) {
      final m = await api.fpMudancas(ancora!);
      if (m['estado'] != 'ok') {
        await _completo();
        return;
      }
      var pendentes = ((m['itens'] as List?) ?? const []).map((j) => ItemFp.deJson(j as Map)).toList();
      // Pais primeiro: o que não acha o pai tenta de novo na volta seguinte.
      for (var volta = 0; volta < 6 && pendentes.isNotEmpty; volta++) {
        final prox = <ItemFp>[];
        for (final it in pendentes) {
          if (!await _aplicar(it)) prox.add(it);
        }
        if (prox.length == pendentes.length) break;
        pendentes = prox;
      }
      if (pendentes.isNotEmpty) _completoPendente = true;
      for (final id in ((m['removidos'] as List?) ?? const []).map((e) => '$e')) {
        final rel = indice[id];
        if (rel == null || rel.isEmpty) continue;
        if (await _apagarLocal(rel)) _ev('removido', rel);
        _tirarDoIndice(rel);
        indice.remove(id);
      }
      ancora = m['ancora'] as String? ?? ancora;
      mais = m['mais'] == true;
      _salvar();
    }
    if (_completoPendente) await _completo();
  }

  /// false = o pai ainda não está no disco (tenta depois).
  Future<bool> _aplicar(ItemFp it) async {
    if (it.id == 'raiz') return true;
    final paiRel = it.pai == null ? null : (it.pai == 'raiz' ? '' : indice[it.pai]);
    if (paiRel == null) return false;
    final novoRel = _junta(paiRel, it.nome);
    final velho = indice[it.id];
    if (velho != null && velho != novoRel && await nativo.estado(_abs(velho)) != null) {
      if (await nativo.estado(_abs(novoRel)) == null) {
        await nativo.mover(_abs(velho), _abs(novoRel));
        _moverIndice(velho, novoRel);
      } else {
        _completoPendente = true;   // o lugar está ocupado aqui: a volta completa resolve
        return true;
      }
    }
    indice[it.id] = novoRel;
    final est = await nativo.estado(_abs(novoRel));
    if (est == null) {
      await nativo.criarPlaceholders(_abs(paiRel), [_np(it)]);
      if (it.pasta) await _popular(it.id, novoRel);   // pasta nova (ou recém-compartilhada): o conteúdo também
      return true;
    }
    if (est.placeholder && idDaIdentidade(est.identidade) == it.id) {
      if (!it.pasta) await _conferirArquivo(novoRel, it, est);
      return true;
    }
    _completoPendente = true;
    return true;
  }

  /// Apaga do disco o que está em dia com a nuvem. O que foi editado aqui (ou
  /// nunca subiu) FICA. true = sumiu tudo.
  Future<bool> _apagarLocal(String rel) async {
    final abs = _abs(rel);
    final est = await nativo.estado(abs);
    if (est == null) return true;
    if (est.pasta) {
      var tudo = true;
      for (final e in Directory(abs).listSync(followLinks: false)) {
        tudo = await _apagarLocal(_junta(rel, p.basename(e.path))) && tudo;
      }
      if (tudo) {
        try {
          await nativo.apagar(abs);
        } catch (_) {
          tudo = false;
        }
      }
      if (tudo) _tirarDoIndice(rel);
      return tudo;
    }
    if ((est.placeholder && est.emDia) || ignorados.nome(_nomeDe(rel))) {
      try {
        await nativo.apagar(abs);
        _tirarDoIndice(rel);
        return true;
      } catch (_) {
        return false;
      }
    }
    return false;
  }

  // ===================================================================
  // disco → nuvem
  // ===================================================================

  /// O observador de pasta viu mudanças nestes caminhos. Junta por um instante e envia.
  void localMudou(Iterable<String> caminhos) {
    for (final c in caminhos) {
      final rel = relDe(c);
      if (rel == null || rel.isEmpty || ignorados.caminho(rel)) continue;
      _sujos.add(rel);
      _recusados.remove(rel);
    }
    _agendar();
  }

  void _agendar() {
    if (_sujos.isEmpty) return;
    _timerSujos?.cancel();
    _timerSujos = Timer(esperaGravacao, () => processarLocais());
  }

  /// Ficou algo para enviar (sem rede, arquivo aberto em outro programa)? O app
  /// chama [processarLocais] de novo a cada ciclo.
  bool get temPendentes => _sujos.isNotEmpty;

  /// Envia o que está pendente (normalmente chamado pelo temporizador do observador).
  Future<void> processarLocais() => _serial(_processar);

  Future<void> _processar() async {
    final lista = _sujos.toList()..sort((a, b) => a.length.compareTo(b.length));
    _sujos.clear();
    final feitos = <String>{};
    for (final rel in lista) {
      if (feitos.any((f) => rel.startsWith('$f/'))) continue;   // a pasta acima já levou
      final r = await _enviarLocal(rel);
      if (r != null) feitos.add(r);
    }
  }

  /// Confere o DISCO inteiro: o que não é placeholder em dia vai para a fila de
  /// envio, e a pasta da nuvem que só perdeu a marca de "em dia" (o Windows a tira
  /// quando algo muda dentro) a recebe de volta quando tudo abaixo dela está em dia.
  ///
  /// ⚠️ É a rede do observador de pasta: o `watcher` do Dart só avisa de ARQUIVO —
  /// pasta nova (vazia) não gera aviso nenhum e ficaria no disco para sempre — e um
  /// observador que cai não avisa ninguém. Roda a cada ciclo do app.
  /// Devolve quantos itens estavam pendentes (0 = tudo em dia).
  Future<int> conferirDisco() => _serial(() async {
        final lista = await nativo.varrer(raiz);
        var pendentes = 0;
        var pastasFora = false;
        for (final e in lista) {
          final rel = relDe(e.caminho);
          if (rel == null || rel.isEmpty || ignorados.caminho(rel)) continue;
          if (e.placeholder && e.pasta) {
            pastasFora = true;
            continue;
          }
          if (_recusados[rel] == _assinatura(rel)) continue;
          _recusados.remove(rel);
          pendentes++;
          _sujos.add(rel);
        }
        if (_sujos.isNotEmpty) await _processar();
        if (pendentes > 0 || pastasFora) await _marcarPastasEmDia();
        return pendentes;
      });

  /// As pastas da nuvem fora de "em dia" sem nada pendente abaixo delas voltam a
  /// "em dia" (e a raiz, quando não sobra nada). Sem isso o Explorer mostraria o
  /// ícone de "sincronizando" na pasta para sempre, mesmo com tudo enviado.
  Future<void> _marcarPastasEmDia() async {
    final lista = await nativo.varrer(raiz);
    final pastas = <String>[];
    final resto = <String>[];
    for (final e in lista) {
      final rel = relDe(e.caminho);
      if (rel == null || rel.isEmpty || ignorados.caminho(rel)) continue;
      (e.placeholder && e.pasta ? pastas : resto).add(rel);
    }
    for (final d in pastas) {
      if (resto.any((r) => r.startsWith('$d/'))) continue;
      await nativo.marcarEmDia(_abs(d));
    }
    if (resto.isEmpty) await nativo.marcarEmDia(raiz);
  }

  String _assinatura(String rel) {
    try {
      final st = FileStat.statSync(_abs(rel));
      if (st.type == FileSystemEntityType.notFound) return '';
      return '${st.type}|${st.size}|${st.modified.millisecondsSinceEpoch}';
    } catch (_) {
      return '';
    }
  }

  /// Um problema que não se resolve sozinho: aparece na tela e não é tentado de
  /// novo enquanto o arquivo/pasta não mudar.
  void _problema(String rel, String msg) {
    _recusados[rel] = _assinatura(rel);
    _ev('problema', rel, msg);
  }

  /// Envia o que mudou em [rel] (arquivo novo, pasta nova ou edição). Devolve o
  /// caminho efetivamente tratado (uma pasta-mãe que ainda não subiu leva junto).
  Future<String?> _enviarLocal(String rel) async {
    var est = await nativo.estado(_abs(rel));
    if (est == null || (est.placeholder && est.emDia)) return null;
    // A pasta-mãe ainda não é da nuvem? Ela sobe primeiro, com tudo dentro.
    var alvo = rel;
    var pai = _paiDe(rel);
    while (pai.isNotEmpty) {
      final ep = await nativo.estado(_abs(pai));
      if (ep == null) return null;
      if (ep.placeholder) break;
      alvo = pai;
      est = ep;
      pai = _paiDe(pai);
    }
    try {
      if (est!.pasta) {
        if (!est.placeholder) await _criarPastaNaNuvem(alvo);
      } else {
        await _enviarArquivo(alvo, est);
      }
    } on ApiErro catch (e) {
      if (e.transitorio) {
        _sujos.add(alvo);   // sem rede: tenta no próximo ciclo
      } else {
        _problema(alvo, e.status == 403 ? 'Sem permissão para guardar aqui.' : e.mensagem);
      }
    } on FileSystemException {
      _sujos.add(alvo);     // aberto/travado por outro programa: tenta depois
    }
    return alvo;
  }

  Future<void> _criarPastaNaNuvem(String rel) async {
    final idPai = await _idDaPasta(_paiDe(rel));
    final destino = idPai == null ? null : await _destino(idPai);
    if (destino == null) {
      _problema(rel, 'Aqui só dá para guardar dentro de Meu Drive, de um drive ou de uma pasta.');
      return;
    }
    final r = await api.criarPasta(
        espacoId: (destino['espaco_id'] as num?)?.toInt(), pastaId: (destino['pasta_id'] as num?)?.toInt(), nome: _nomeDe(rel));
    final pasta = (r['pasta'] as Map).cast<String, dynamic>();
    final id = 'i${pasta['id']}';
    var fim = rel;
    final nome = '${pasta['nome']}';
    if (nome != _nomeDe(rel)) {
      fim = _junta(_paiDe(rel), nome);
      await nativo.mover(_abs(rel), _abs(fim));
    }
    await nativo.converter(_abs(fim), id);
    indice[id] = fim;
    // E tudo o que já está dentro dela.
    for (final e in Directory(_abs(fim)).listSync(followLinks: false)) {
      final nomeE = p.basename(e.path);
      if (ignorados.nome(nomeE)) continue;
      await _enviarLocal(_junta(fim, nomeE));
    }
  }

  Future<void> _enviarArquivo(String rel, EstadoLocal est) async {
    final f = File(_abs(rel));
    final st1 = f.statSync();
    if (DateTime.now().difference(st1.modified) < esperaGravacao) {
      _sujos.add(rel);   // ainda pode estar sendo gravado
      _agendar();
      return;
    }
    final imp = await Impressao.deArquivo(f);
    final st2 = f.statSync();
    if (imp == null || st2.size != st1.size || st2.modified != st1.modified) {
      _sujos.add(rel);
      return;
    }
    final id = est.placeholder ? idDaIdentidade(est.identidade) : '';
    final n = numeroDoItem(id);
    final base = versaoDaIdentidade(est.identidade);
    if (n != null && base != null) {
      await _enviarVersao(rel, f, imp, st2, n, base);
    } else {
      await _enviarNovo(rel, f, imp, st2, est.placeholder);
    }
  }

  Future<void> _enviarNovo(String rel, File f, Impressao imp, FileStat st, bool jaPlaceholder) async {
    final idPai = await _idDaPasta(_paiDe(rel));
    final destino = idPai == null ? null : await _destino(idPai);
    if (destino == null) {
      _problema(rel, 'Aqui só dá para guardar dentro de Meu Drive, de um drive ou de uma pasta.');
      return;
    }
    final r = await enviarConteudo(api, f, imp, st, {'nome': _nomeDe(rel), ...destino});
    if (r == null) {
      _sujos.add(rel);
      return;
    }
    final item = ItemFp('i${r.item['id']}', null, '${r.item['nome']}', false, versao: (r.item['versao'] as num?)?.toInt() ?? 1);
    var fim = rel;
    if (item.nome != _nomeDe(rel)) {
      fim = _junta(_paiDe(rel), item.nome);
      await nativo.mover(_abs(rel), _abs(fim));
    }
    if (jaPlaceholder) {
      await nativo.atualizar(_abs(fim), item.identidade, tamanho: imp.tamanho, desidratar: liberarAposEnviar);
    } else {
      await nativo.converter(_abs(fim), item.identidade, desidratar: liberarAposEnviar);
    }
    indice[item.id] = fim;
    _ev('enviado', fim);
  }

  Future<void> _enviarVersao(String rel, File f, Impressao imp, FileStat st, int n, int base) async {
    EnvioConcluido? r;
    try {
      r = await enviarConteudo(api, f, imp, st, {'nome': _nomeDe(rel), 'item_id': n, 'base_versao': base});
    } on ApiErro catch (e) {
      if (e.status != 404) rethrow;
      // Apagado na nuvem enquanto era editado aqui: sobe como arquivo novo.
      await _enviarNovo(rel, f, imp, st, true);
      return;
    }
    if (r == null) {
      _sujos.add(rel);
      return;
    }
    final v = (r.item['versao'] as num?)?.toInt() ?? base + 1;
    if (!r.conflito) {
      await nativo.atualizar(_abs(rel), 'i$n:$v', tamanho: imp.tamanho, desidratar: liberarAposEnviar);
      _ev('enviado', rel);
      return;
    }
    // A nuvem mudou antes: o que subiu virou a CÓPIA DE CONFLITO. O arquivo daqui
    // passa a ser a cópia, e o original volta como placeholder (só nuvem).
    final copia = 'i${r.item['id']}';
    final copiaRel = _junta(_paiDe(rel), '${r.item['nome']}');
    await nativo.mover(_abs(rel), _abs(copiaRel));
    await nativo.atualizar(_abs(copiaRel), '$copia:$v', tamanho: imp.tamanho, desidratar: liberarAposEnviar);
    indice[copia] = copiaRel;
    final original = ItemFp.deJson(await api.fpItem('i$n'));
    await nativo.criarPlaceholders(_abs(_paiDe(rel)), [_np(original)]);
    indice[original.id] = _junta(_paiDe(rel), original.nome);
    _ev('conflito', copiaRel, 'a nuvem tinha uma versão mais nova; a sua foi guardada com este nome');
  }

  // ===================================================================
  // O Windows pergunta (o usuário apagou / renomeou um placeholder)
  // ===================================================================

  /// true = pode apagar (foi para a lixeira do NN Cloud).
  Future<bool> aoApagar(String identidade, String caminho) async {
    final n = numeroDoItem(idDaIdentidade(identidade));
    if (n == null) return false;   // pastas fixas e drives não se apagam
    try {
      // A recusa vem ITEM A ITEM (`ok: false`) numa resposta 200 — não só como erro HTTP.
      final r = await api.lixeira([n], confirmado: true);
      final it = r.isEmpty ? null : r.first;
      if (it != null && it['ok'] != true) {
        throw ApiErro((it['codigo'] as num?)?.toInt() ?? 422, '${it['erro'] ?? 'O item não foi para a lixeira.'}');
      }
    } on ApiErro catch (e) {
      if (e.status != 404) {
        _ev('problema', relDe(caminho) ?? caminho, e.status == 403 ? 'Sem permissão para apagar.' : e.mensagem);
        return false;
      }
    }
    indice.remove('i$n');
    final rel = relDe(caminho);
    if (rel != null) _tirarDoIndice(rel);
    _ev('removido', rel ?? caminho);
    return true;
  }

  /// true = pode renomear/mover. Para fora da pasta (ex.: Lixeira do Windows) = apagar.
  Future<bool> aoRenomear(String identidade, String de, String para) async {
    final relPara = relDe(para);
    if (relPara == null) return aoApagar(identidade, de);
    final relDeC = relDe(de);
    final n = numeroDoItem(idDaIdentidade(identidade));
    if (n == null || relDeC == null || relPara.isEmpty) return false;
    try {
      final paiNovo = _paiDe(relPara), paiVelho = _paiDe(relDeC);
      if (paiNovo != paiVelho) {
        final idPai = await _idDaPasta(paiNovo);
        final destino = idPai == null ? null : await _destino(idPai);
        if (destino == null) return false;
        await api.mover(n, espacoId: (destino['espaco_id'] as num?)?.toInt(), pastaId: (destino['pasta_id'] as num?)?.toInt());
      }
      if (_nomeDe(relPara) != _nomeDe(relDeC)) await api.renomear(n, _nomeDe(relPara));
    } on ApiErro catch (e) {
      _ev('problema', relDeC, e.status == 403 ? 'Sem permissão para mover ou renomear.' : e.mensagem);
      return false;
    }
    _moverIndice(relDeC, relPara);
    indice['i$n'] = relPara;
    return true;
  }

  // ===================================================================
  // Abrir: o Windows pede o conteúdo
  // ===================================================================

  /// Baixa o conteúdo de [identidade] para [destino] (conferido pela impressão).
  /// [aoReceber] recebe o total já gravado. Lança [ApiErro] se não deu.
  Future<int> baixar(String identidade, File destino, {void Function(int gravados)? aoReceber}) async {
    final n = numeroDoItem(idDaIdentidade(identidade));
    if (n == null) throw const ApiErro(404, 'Item não encontrado.');
    final imp = await baixarConteudo(api, n, destino, aoReceber: aoReceber);
    return imp.tamanho;
  }

  void encerrar() {
    _timerSujos?.cancel();
    _timerSujos = null;
  }
}
