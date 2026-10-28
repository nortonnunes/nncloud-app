// O "cérebro" do aplicativo: conexão, ciclo de sincronização, observadores de
// pasta, pausa, notificações e o que as telas mostram.
//
// Ritmo: uma consulta de mudanças a cada `intervalo_seg` (30 s); o observador
// de arquivos marca a pasta e antecipa o ciclo (3 s depois do último aviso);
// varredura completa a cada 10 min mesmo sem aviso; ao acordar da suspensão
// (o relógio pulou), varre tudo. Sem rede: tenta de novo com espera crescente.
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nncloud_motor/motor.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';
import 'package:watcher/watcher.dart';

import '../config.dart';
import '../widgets/cabecalho.dart' show bytesTexto;
import 'armazenamento.dart';
import 'notificacoes.dart';
import 'sistema.dart';

enum Situacao { desconectado, conectando, ok, sincronizando, offline, pausado, erro }

class LinhaAtividade {
  final DateTime quando;
  final String tipo, caminho;
  final int? par, tamanho;
  final String? detalhe;
  LinhaAtividade(this.tipo, this.caminho, {this.par, this.tamanho, this.detalhe, DateTime? quando}) : quando = quando ?? DateTime.now();
}

class Controle extends ChangeNotifier {
  final Armazenamento arm;
  final Notificacoes notif;
  Controle(this.arm, this.notif);

  Api? api;
  Sincronizador? _sinc;
  Situacao situacao = Situacao.desconectado;
  String? mensagem;
  Map<String, dynamic>? eu;
  List<Map<String, dynamic>> pares = [];
  Map<int, ResultadoPar> resultados = {};
  final List<LinhaAtividade> atividade = [];
  final List<ExclusaoEmMassa> aguardando = [];
  bool janelaVisivel = true;

  // Conexão por código.
  String? codigo;
  String? urlConectar;
  bool _pararEspera = false;

  // Progresso do ciclo em curso.
  int bytesCiclo = 0, arquivosCiclo = 0;
  String? arquivoAtual;
  DateTime? ultimoSync;

  Timer? _timer, _antecipar;
  final Map<int, StreamSubscription<WatchEvent>> _observadores = {};
  bool _rodando = false;
  DateTime _ultimoTique = DateTime.now();
  int _falhasSeguidas = 0;

  bool get pausado => arm.pref<bool>('pausado', false);
  bool get notificar => arm.pref<bool>('notificacoes', true);
  String get baseApi => arm.pref<String>('api', AppConfig.apiPadrao);
  int get intervalo => (eu?['config']?['intervalo_seg'] as int?) ?? 30;
  String get nomeComputador => Platform.localHostname.replaceAll(RegExp(r'\.local$'), '');
  String get plataforma => Platform.isWindows ? 'windows' : 'macos';

  int get pendentes => resultados.values.fold(0, (s, r) => s + r.pendentes);
  List<String> get problemas => [for (final r in resultados.values) ...r.problemas];
  int get arquivosSincronizados {
    var n = 0;
    for (final pr in pares) {
      n += (pr['arquivos'] as int?) ?? 0;
    }
    return n;
  }

  // ===================================================================
  // Início, conexão e desconexão
  // ===================================================================

  Future<void> iniciar() async {
    final t = await arm.token();
    if (t == null) {
      situacao = Situacao.desconectado;
      notifyListeners();
      return;
    }
    api = Api(baseApi, token: t, proxy: arm.pref<String>('proxy', ''), versaoApp: AppConfig.versao);
    await _carregarConta();
  }

  Future<void> _carregarConta() async {
    situacao = Situacao.conectando;
    notifyListeners();
    try {
      eu = await api!.eu();
      await _recarregarPares();
      _criarSincronizador();
      situacao = pausado ? Situacao.pausado : Situacao.ok;
      mensagem = null;
      _agendar(const Duration(seconds: 1));
    } on ApiErro catch (e) {
      if (e.desconectado) {
        await _esquecerConta('Este computador foi desconectado do NN Cloud. Conecte de novo.');
        return;
      }
      situacao = Situacao.offline;
      mensagem = e.mensagem;
      _agendar(const Duration(seconds: 30), recarregarConta: true);
    }
    notifyListeners();
  }

  void _criarSincronizador() {
    final cfg = (eu?['config'] as Map?)?.cast<String, dynamic>() ?? {};
    final extras = (arm.pref<List>('ignorados_extra', const [])).cast<String>();
    final padrao = ((cfg['ignorados'] as List?) ?? ignoradosPadrao).cast<String>();
    _sinc = Sincronizador(
      api: api!,
      dados: arm.dados,
      computador: nomeComputador,
      ignorados: Ignorados([...padrao, ...extras]),
      aoEvento: _aoEvento,
    );
  }

  /// Pede o código e espera a pessoa autorizar no navegador.
  Future<void> conectar() async {
    final a = Api(baseApi, proxy: arm.pref<String>('proxy', ''), versaoApp: AppConfig.versao);
    situacao = Situacao.conectando;
    mensagem = null;
    notifyListeners();
    try {
      final r = await a.conectar(nomeComputador, plataforma);
      codigo = r['codigo'] as String;
      urlConectar = '${r['url']}?codigo=${Uri.encodeComponent(codigo!)}';
      notifyListeners();
      await abrirNavegador(urlConectar!);
      final segredo = r['segredo'] as String;
      var espera = (r['intervalo'] as int?) ?? 5;
      final limite = DateTime.now().add(Duration(seconds: (r['expira_em_seg'] as int?) ?? 600));
      _pararEspera = false;
      while (!_pararEspera && DateTime.now().isBefore(limite)) {
        await Future<void>.delayed(Duration(seconds: espera));
        if (_pararEspera) break;
        final t = await a.buscarToken(segredo);
        switch (t['status']) {
          case 'aprovado':
            await arm.gravarToken(t['token'] as String);
            codigo = null;
            api = Api(baseApi, token: t['token'] as String, proxy: arm.pref<String>('proxy', ''), versaoApp: AppConfig.versao);
            await _carregarConta();
            return;
          case 'lento':
            espera += 2;
          case 'recusado':
            codigo = null;
            situacao = Situacao.desconectado;
            mensagem = 'A conexão foi recusada no navegador.';
            notifyListeners();
            return;
          case 'expirado':
            break;
        }
      }
      codigo = null;
      situacao = Situacao.desconectado;
      mensagem = _pararEspera ? null : 'O código expirou. Peça um novo.';
    } on ApiErro catch (e) {
      codigo = null;
      situacao = Situacao.desconectado;
      mensagem = e.mensagem;
    } finally {
      a.fechar();
    }
    notifyListeners();
  }

  void cancelarConexao() {
    _pararEspera = true;
    codigo = null;
    situacao = Situacao.desconectado;
    notifyListeners();
  }

  Future<void> desconectar() async {
    try {
      await api?.desconectar();
    } on ApiErro {
      // desconecta localmente mesmo sem rede
    }
    await _esquecerConta(null);
  }

  Future<void> _esquecerConta(String? msg) async {
    _timer?.cancel();
    for (final o in _observadores.values) {
      await o.cancel();
    }
    _observadores.clear();
    await arm.gravarToken(null);
    api?.fechar();
    api = null;
    _sinc = null;
    eu = null;
    pares = [];
    resultados = {};
    situacao = Situacao.desconectado;
    mensagem = msg;
    if (msg != null && notificar) await notif.mostrar('NN Cloud', msg);
    notifyListeners();
  }

  // ===================================================================
  // Pares (pastas sincronizadas)
  // ===================================================================

  Future<void> _recarregarPares() async {
    pares = await api!.pares();
    _ajustarObservadores();
  }

  List<ConfigPar> _configs() => [
        for (final pr in pares)
          ConfigPar(
            id: pr['id'] as int,
            raiz: pr['caminho_local'] as String,
            espacoId: pr['espaco_id'] as int,
            raizId: pr['raiz_id'] as int?,
            nome: (pr['nome'] as String?) ?? '',
            pausado: pausado || (arm.pref<List>('pares_pausados', const [])).contains(pr['id']),
            envio: pr['modo'] == 'envio',
            soNuvem: {for (final x in (pr['so_nuvem'] as List?) ?? const []) if (x is int) x},
          ),
      ];

  /// Pasta de envio (tudo sobe e sai do computador) ou espelho (iguais nos
  /// dois sentidos), e as subpastas que ficam só na nuvem neste computador.
  Future<String?> salvarOpcoesPar(int id, {required bool envio, required Set<int> soNuvem}) async {
    try {
      await api!.atualizarPar(id, {'modo': envio ? 'envio' : 'espelho', 'so_nuvem': soNuvem.toList()});
      await _recarregarPares();
      _sinc?.marcarSujo(id);
      notifyListeners();
      sincronizarAgora();
      return null;
    } on ApiErro catch (e) {
      return e.mensagem;
    }
  }

  /// Quanto há na nuvem (dentro de uma pasta, ou o par inteiro), pela árvore que
  /// o aplicativo já conhece — para avisar quanto vai descer.
  ({int arquivos, int bytes}) tamanhoNaNuvem(int par, {int? pastaId}) =>
      _sinc?.tamanhoNaNuvem(par, pastaId: pastaId) ?? (arquivos: 0, bytes: 0);

  /// Cria um par: pasta do computador → destino na nuvem.
  /// `destino`: null = "Meu Drive, numa pasta com o mesmo nome".
  Future<String?> adicionarPar(String pastaLocal, {int? espacoId, int? pastaId, bool mesmoNome = false, bool envio = false}) async {
    final recusa = motivoPastaRecusada(pastaLocal, [for (final pr in pares) pr['caminho_local'] as String]);
    if (recusa != null && recusa != 'rede') return recusa;
    try {
      var esp = espacoId ?? (eu!['meu_drive']['id'] as int);
      int? raiz = pastaId;
      if (mesmoNome) {
        final nome = p.basename(pastaLocal);
        final existentes = await api!.pastas(espacoId: pastaId == null ? esp : null, pastaId: pastaId);
        final ja = (existentes['pastas'] as List).cast<Map<String, dynamic>>().where((x) => chaveNome(x['nome'] as String) == chaveNome(nome));
        if (ja.isNotEmpty) {
          raiz = ja.first['id'] as int;
        } else {
          final criada = await api!.criarPasta(espacoId: pastaId == null ? esp : null, pastaId: pastaId, nome: nfc(nome));
          raiz = (criada['pasta'] as Map)['id'] as int;
        }
      }
      await api!.criarPar(espacoId: esp, raizId: raiz, caminhoLocal: pastaLocal, nome: p.basename(pastaLocal), modo: envio ? 'envio' : 'espelho');
      await _recarregarPares();
      sincronizarAgora();
      return null;
    } on ApiErro catch (e) {
      return e.mensagem;
    }
  }

  Future<String?> removerPar(int id) async {
    try {
      final pr = pares.firstWhere((x) => x['id'] == id);
      await api!.removerPar(id);
      final marcador = File(p.join(pr['caminho_local'] as String, nomeMarcador));
      if (marcador.existsSync()) marcador.deleteSync();
      final d = Directory(p.join(arm.dados.path, 'pares', '$id'));
      if (d.existsSync()) d.deleteSync(recursive: true);
      _sinc?.esquecer();
      await _recarregarPares();
      resultados.remove(id);
      notifyListeners();
      return null;
    } on ApiErro catch (e) {
      return e.mensagem;
    } on FileSystemException catch (e) {
      return e.message;
    }
  }

  void pausarPar(int id, bool pausar) {
    final l = (arm.pref<List>('pares_pausados', const [])).cast<int>().toSet();
    pausar ? l.add(id) : l.remove(id);
    arm.definir('pares_pausados', l.toList());
    if (!pausar) sincronizarAgora();
    notifyListeners();
  }

  void _ajustarObservadores() {
    final ids = pares.map((x) => x['id'] as int).toSet();
    for (final id in _observadores.keys.toList()) {
      if (!ids.contains(id)) _observadores.remove(id)?.cancel();
    }
    for (final pr in pares) {
      final id = pr['id'] as int;
      if (_observadores.containsKey(id)) continue;
      final raiz = pr['caminho_local'] as String;
      if (!Directory(raiz).existsSync()) continue;
      try {
        _observadores[id] = DirectoryWatcher(raiz).events.listen((ev) {
          final nome = p.basename(ev.path);
          if (nome.startsWith('.nncloud')) return;   // os nossos temporários e a lixeira local
          if (ev.path.contains('${p.separator}$pastaLixeiraLocal${p.separator}')) return;
          _sinc?.marcarSujo(id);
          _antecipar?.cancel();
          _antecipar = Timer(const Duration(seconds: 3), sincronizarAgora);
        }, onError: (_) {});
      } catch (_) {
        // sem observador, a varredura de 10 em 10 minutos cobre
      }
    }
  }

  // ===================================================================
  // Ciclo
  // ===================================================================

  void _agendar(Duration d, {bool recarregarConta = false}) {
    _timer?.cancel();
    _timer = Timer(d, () => recarregarConta ? _carregarConta() : _tique());
  }

  void sincronizarAgora() {
    if (_rodando || api == null) return;
    _agendar(Duration.zero);
  }

  Future<void> pausar(bool p) async {
    arm.definir('pausado', p);
    situacao = p ? Situacao.pausado : Situacao.ok;
    notifyListeners();
    if (!p) sincronizarAgora();
  }

  void confirmarExclusao(int par) {
    _sinc?.confirmarExclusoes(par);
    aguardando.removeWhere((e) => e.par == par);
    notifyListeners();
    sincronizarAgora();
  }

  void manterExclusao(int par) {
    aguardando.removeWhere((e) => e.par == par);
    notifyListeners();
  }

  Future<void> _tique() async {
    if (_rodando || _sinc == null) return;
    // Acordou da suspensão (ou o relógio pulou): varre tudo.
    final agora = DateTime.now();
    if (agora.difference(_ultimoTique).inSeconds > intervalo * 2 + 60) _sinc!.marcarTodosSujos();
    _ultimoTique = agora;
    if (pausado) {
      situacao = Situacao.pausado;
      notifyListeners();
      _agendar(Duration(seconds: intervalo));
      return;
    }
    _rodando = true;
    situacao = Situacao.sincronizando;
    bytesCiclo = 0;
    arquivosCiclo = 0;
    notifyListeners();
    var proximo = Duration(seconds: intervalo);
    try {
      await _recarregarPares();
      final r = await _sinc!.ciclo(_configs());
      resultados = {for (final x in r) x.par: x};
      final offline = r.any((x) => x.estado == 'offline');
      final erro = r.where((x) => x.estado == 'erro').toList();
      for (final x in r.where((x) => x.exclusao != null)) {
        if (!aguardando.any((e) => e.par == x.par)) {
          aguardando.add(x.exclusao!);
          if (notificar) {
            await notif.mostrar('Confirmação necessária', '${x.exclusao!.total} itens seriam apagados de uma vez. Abra o NN Cloud para confirmar.');
          }
        }
      }
      if (offline) {
        _falhasSeguidas++;
        situacao = Situacao.offline;
        mensagem = r.firstWhere((x) => x.estado == 'offline').mensagem;
        proximo = Duration(seconds: (intervalo * (1 << (_falhasSeguidas.clamp(0, 4)))).clamp(30, 600));
      } else {
        _falhasSeguidas = 0;
        situacao = erro.isNotEmpty ? Situacao.erro : Situacao.ok;
        mensagem = erro.isNotEmpty ? erro.first.mensagem : null;
        ultimoSync = DateTime.now();
      }
      await _avisos(r);
      eu = await api!.eu().catchError((_) => eu!);
      await _limparLixeirasLocais();
    } on ApiErro catch (e) {
      if (e.desconectado) {
        _rodando = false;
        await _esquecerConta('Este computador foi desconectado do NN Cloud. Conecte de novo.');
        return;
      }
      _falhasSeguidas++;
      situacao = Situacao.offline;
      mensagem = e.mensagem;
      proximo = Duration(seconds: (30 * (1 << (_falhasSeguidas.clamp(0, 4)))).clamp(30, 600));
    } catch (e) {
      situacao = Situacao.erro;
      mensagem = 'Falha inesperada: $e';
    } finally {
      _rodando = false;
      arquivoAtual = null;
      notifyListeners();
      _agendar(proximo);
    }
  }

  Future<void> _avisos(List<ResultadoPar> r) async {
    if (!notificar) return;
    final env = r.fold(0, (s, x) => s + x.enviados), bai = r.fold(0, (s, x) => s + x.baixados);
    final conf = r.fold(0, (s, x) => s + x.conflitos);
    final lib = r.fold(0, (s, x) => s + x.liberados), libBytes = r.fold(0, (s, x) => s + x.bytesLiberados);
    if (!janelaVisivel && lib > 0) {
      await notif.mostrar('Espaço liberado', '$lib arquivo(s) estão só na nuvem agora — ${bytesTexto(libBytes)} a menos neste computador.');
    }
    if (!janelaVisivel && env + bai > 0) {
      await notif.mostrar('NN Cloud', 'Sincronização concluída: ${env + bai} arquivo(s) atualizado(s).');
    }
    if (conf > 0) {
      await notif.mostrar('Arquivo alterado nos dois lados', 'Guardamos as duas versões. Procure "(conflito de …)" na pasta.');
    }
    for (final x in r.where((x) => x.estado == 'erro' && x.mensagem != null)) {
      final avisado = arm.pref<String>('ultimo_erro_${x.par}', '');
      if (avisado != x.mensagem) {
        arm.definir('ultimo_erro_${x.par}', x.mensagem);
        await notif.mostrar('NN Cloud parou uma pasta', x.mensagem!);
      }
    }
    final nova = (eu?['app']?[plataforma]?['versao'] as String?);
    if (nova != null && _maior(nova, AppConfig.versao) && arm.pref<String>('versao_avisada', '') != nova) {
      arm.definir('versao_avisada', nova);
      await notif.mostrar('Nova versão do NN Cloud', 'A versão $nova está disponível em Configurações → Sobre.');
    }
  }

  static bool _maior(String a, String b) {
    List<int> v(String s) => s.split(RegExp(r'[.+-]')).take(3).map((x) => int.tryParse(x) ?? 0).toList();
    final x = v(a), y = v(b);
    for (var i = 0; i < 3; i++) {
      if (x[i] != y[i]) return x[i] > y[i];
    }
    return false;
  }

  Future<void> _limparLixeirasLocais() async {
    final hoje = DateTime.now().toIso8601String().substring(0, 10);
    if (arm.pref<String>('lixeira_limpa_em', '') == hoje) return;
    arm.definir('lixeira_limpa_em', hoje);
    for (final pr in pares) {
      try {
        Sincronizador.limparLixeiraLocal(pr['caminho_local'] as String, AppConfig.diasLixeiraLocal);
      } catch (_) {
        // tenta amanhã
      }
    }
  }

  void _aoEvento(Evento e) {
    switch (e.tipo) {
      case 'progresso':
        bytesCiclo += e.tamanho ?? 0;
        arquivoAtual = e.caminho;
      case 'enviado' || 'baixado' || 'conflito' || 'erro' || 'pausado' || 'liberado':
        if (e.tipo == 'enviado' || e.tipo == 'baixado') arquivosCiclo++;
        atividade.insert(0, LinhaAtividade(e.tipo, e.caminho ?? '', par: e.par, tamanho: e.tamanho, detalhe: e.detalhe));
        if (atividade.length > 300) atividade.removeLast();
    }
    notifyListeners();
  }

  // ===================================================================
  // Utilidades
  // ===================================================================

  /// Nunca lança: sem navegador, a tela mostra o endereço para copiar.
  Future<void> abrirNavegador(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      // o botão "Copiar endereço" cobre
    }
  }

  Future<void> abrirPasta(String caminho) async {
    if (Platform.isMacOS) {
      await Process.run('open', [caminho]);
    } else if (Platform.isWindows) {
      await Process.run('explorer', [caminho]);
    }
  }

  Future<void> mostrarNoGerenciador(String caminhoAbs) async {
    if (Platform.isMacOS) {
      await Process.run('open', ['-R', caminhoAbs]);
    } else if (Platform.isWindows) {
      await Process.run('explorer', ['/select,', caminhoAbs]);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _antecipar?.cancel();
    for (final o in _observadores.values) {
      o.cancel();
    }
    super.dispose();
  }
}
