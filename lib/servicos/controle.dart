// O estado do aplicativo: login → sessão.
//
//   login      sem sessão: o login igual ao do site, em etapas (ver `EtapaLogin`)
//   pronto     logado: as consultas periódicas rodam (comunicados mesmo com a
//              janela na bandeja)
//   bloqueado  app desligado no NN Conecta ou servidor fora do ar
//
// O login:
//   senha → [política de uso] → verificação em duas etapas (código do app
//   autenticador OU do e-mail, ou aprovação no celular) | configurar o app
//   autenticador | isento → sessão
//   QR code lido com o app NN Conecta do celular → [política] → sessão
//
// Entre as etapas o servidor dá um TICKET (`nnconvl_…`), que viaja no corpo e só
// vive na memória (15 min). O token da sessão (`nnconv_…`) vai para o chaveiro.
// Perder a sessão (expirou, encerrada pelo administrador, perdeu a permissão de
// Conversas) volta ao login, mantendo o e-mail.
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../api/cliente.dart';
import '../config.dart';
import 'armazenamento.dart';

enum Fase { iniciando, login, pronto, bloqueado }

/// As telas do login. `qr` é o caminho alternativo, sem senha.
enum EtapaLogin { senha, politica, doisFatores, setup, qr }

const _p = AppConfig.prefixo;

class Controle extends ChangeNotifier {
  final Armazenamento arm;
  final Api api;
  Controle(this.arm, {Api? api}) : api = api ?? Api() {
    this.api.aoPerderAcesso = _perdeuAcesso;
  }

  Fase fase = Fase.iniciando;
  String? motivo;           // texto da tela de bloqueio
  String? codigoBloqueio;   // `error.code` do bloqueio (app_desligado, sem_rede…)
  String nomeComputador = '';

  // Login
  EtapaLogin etapa = EtapaLogin.senha;
  String? ticket;
  Map<String, dynamic> passo = {};
  int restamTentativas = 5;
  String emailDigitado = '';
  /// Aviso no topo da tela de login ("Sua sessão expirou…").
  String? avisoLogin;

  // Aprovação no celular
  String? celularStatus;    // pendente | aprovado | recusado | expirado
  int celularRestam = 0;
  Timer? _tCelular;

  // QR code
  Map<String, dynamic>? qr; // token, segredo, payload, ttl
  String qrStatus = '';     // pending | approved | expired
  DateTime? qrCriado;
  Timer? _tQr;
  bool _concluindo = false;

  // Sessão
  Map<String, dynamic>? aparencia;
  Map<String, dynamic>? eu;
  String modo = 'claro';
  int naoLidas = 0;
  List<Map<String, dynamic>> comunicados = [];
  final Set<int> _comunicadosVistos = {};

  /// A janela está à vista? (fora dela, mensagem nova vira notificação + som)
  bool janelaVisivel = true;

  /// Avisos para a casca (janela, som, notificação) — ligados no `main`.
  Future<void> Function(List<Map<String, dynamic>> novos)? aoChegarComunicado;
  Future<void> Function(int antes, int agora)? aoChegarMensagem;
  void Function()? aoMudarVisual;

  Timer? _tComunicados, _tEu, _tAparencia;
  bool _carregandoEu = false;

  bool get escuro => modo == 'escuro';
  String get primeiroNome => (eu?['primeiro'] ?? '').toString();
  int get meuId => (eu?['id'] as num?)?.toInt() ?? 0;
  bool get podeCriarGrupo => ((eu?['pode'] as Map?)?['criar_grupo']) == true;
  bool get podeNews => ((eu?['pode'] as Map?)?['news']) == true;

  /* ======================= início ======================= */

  Future<void> iniciar() async {
    api.token = await arm.token();
    nomeComputador = _nomeDoComputador();
    emailDigitado = arm.pref<String>('ultimo_email', '');
    await _carregarAparencia();
    if (api.token != null) {
      await _entrarComSessao();
    } else {
      await _conferirServidor();
    }
  }

  /// Sem sessão: o app está ligado no servidor? (o login é público)
  Future<void> _conferirServidor() async {
    try {
      await api.get('$_p/app');
      _irParaLogin();
    } on ApiErro catch (e) {
      _bloquear(e);
    }
  }

  Map<String, dynamic> get _contexto => {'dispositivo': nomeComputador, 'so': AppConfig.so, 'versao': AppConfig.versao};

  /* ======================= login: senha ======================= */

  Future<String?> entrar(String email, String senha) async {
    emailDigitado = email.trim();
    avisoLogin = null;
    try {
      final r = await api.post('$_p/login', {'email': emailDigitado, 'senha': senha, ..._contexto}) as Map;
      arm.definir('ultimo_email', emailDigitado);
      return await _respostaLogin(r);
    } on ApiErro catch (e) {
      return _erroLogin(e);
    }
  }

  /* ======================= login: política ======================= */

  Future<String?> aceitarPolitica(String cpf) async {
    try {
      final r = await api.post('$_p/login/politica', {'ticket': ticket, 'cpf': cpf, 'aceite': true}) as Map;
      return await _respostaLogin(r);
    } on ApiErro catch (e) {
      return _erroLogin(e);
    }
  }

  /* ======================= login: 2FA ======================= */

  /// O código do app autenticador OU o do e-mail (o mesmo campo, como no site).
  Future<String?> enviarCodigo(String codigo) => _passoComCodigo('$_p/login/codigo', codigo);

  /// Configurando o app autenticador: confirma o primeiro código.
  Future<String?> confirmarSetup(String codigo) => _passoComCodigo('$_p/login/setup', codigo);

  /// Configurando: entrar só desta vez com o código do e-mail.
  Future<String?> entrarComCodigoDoEmail(String codigo) => _passoComCodigo('$_p/login/email/entrar', codigo);

  Future<String?> _passoComCodigo(String rota, String codigo) async {
    try {
      final r = await api.post(rota, {'ticket': ticket, 'codigo': codigo.replaceAll(RegExp(r'\D'), '')}) as Map;
      return await _respostaLogin(r);
    } on ApiErro catch (e) {
      if (e.codigo == 'codigo_invalido') {
        restamTentativas = (restamTentativas - 1).clamp(0, 5);
        notifyListeners();
      }
      return _erroLogin(e);
    }
  }

  /// "Enviar código por e-mail". Devolve a mensagem do servidor (sucesso ou recusa).
  Future<({bool ok, String msg})> pedirCodigoEmail() async {
    try {
      final r = await api.post('$_p/login/email', {'ticket': ticket}) as Map;
      final pend = r['pendente'];
      if (pend is Map) {
        final email = Map<String, dynamic>.from((passo['email'] as Map?) ?? const {});
        email['pendente'] = pend;
        passo = {...passo, 'email': email};
        notifyListeners();
      }
      return (ok: true, msg: (r['msg'] ?? 'Código enviado.').toString());
    } on ApiErro catch (e) {
      final m = _erroLogin(e);
      return (ok: false, msg: m ?? e.mensagem);
    }
  }

  /* ======================= login: celular ======================= */

  Future<String?> pedirCelular({bool reenviar = false}) async {
    try {
      final r = await api.post('$_p/login/celular', {'ticket': ticket, 'reenviar': reenviar}) as Map;
      celularStatus = 'pendente';
      celularRestam = (r['restam'] as num?)?.toInt() ?? 120;
      notifyListeners();
      _tCelular?.cancel();
      _tCelular = Timer.periodic(AppConfig.cicloAprovacao, (_) => _vigiarCelular());
      return null;
    } on ApiErro catch (e) {
      return _erroLogin(e);
    }
  }

  Future<void> _vigiarCelular() async {
    if (etapa != EtapaLogin.doisFatores || ticket == null) {
      _tCelular?.cancel();
      return;
    }
    try {
      final r = await api.post('$_p/login/celular/estado', {'ticket': ticket}) as Map;
      celularStatus = r['status']?.toString();
      celularRestam = (r['restam'] as num?)?.toInt() ?? 0;
      notifyListeners();
      if (celularStatus == 'aprovado' && !_concluindo) {
        _tCelular?.cancel();
        _concluindo = true;
        try {
          final s = await api.post('$_p/login/celular/entrar', {'ticket': ticket}) as Map;
          await _respostaLogin(s);
        } finally {
          _concluindo = false;
        }
      } else if (celularStatus != 'pendente') {
        _tCelular?.cancel();
      }
    } on ApiErro catch (e) {
      _tCelular?.cancel();
      _erroLogin(e);
    }
  }

  void pararCelular() {
    _tCelular?.cancel();
    celularStatus = null;
    notifyListeners();
  }

  /* ======================= login: QR code ======================= */

  Future<String?> iniciarQr() async {
    _pararQr();
    avisoLogin = null;
    try {
      final r = await api.post('$_p/qr', _contexto) as Map;
      qr = r.cast<String, dynamic>();
      qrStatus = 'pending';
      qrCriado = DateTime.now();
      etapa = EtapaLogin.qr;
      notifyListeners();
      _tQr = Timer.periodic(AppConfig.cicloAprovacao, (_) => _vigiarQr());
      return null;
    } on ApiErro catch (e) {
      etapa = EtapaLogin.qr;
      qr = null;
      notifyListeners();
      return _erroLogin(e);
    }
  }

  /// Segundos que o QR ainda vale.
  int get qrRestam {
    final ttl = (qr?['ttl'] as num?)?.toInt() ?? 120;
    final c = qrCriado;
    if (c == null) return 0;
    return (ttl - DateTime.now().difference(c).inSeconds).clamp(0, ttl);
  }

  Future<void> _vigiarQr() async {
    final q = qr;
    if (etapa != EtapaLogin.qr || q == null) {
      _pararQr();
      return;
    }
    if (qrRestam <= 0) {
      qrStatus = 'expired';
      _pararQr();
      notifyListeners();
      return;
    }
    try {
      final r = await api.post('$_p/qr/estado', {'token': q['token'], 'segredo': q['segredo']}) as Map;
      qrStatus = (r['status'] ?? '').toString();
      notifyListeners();
      if (qrStatus == 'approved' && !_concluindo) {
        _pararQr();
        _concluindo = true;
        try {
          final s = await api.post('$_p/qr/entrar', {'token': q['token'], 'segredo': q['segredo'], ..._contexto}) as Map;
          qr = null;
          final erro = await _respostaLogin(s);
          if (erro != null) avisoLogin = erro;
        } on ApiErro catch (e) {
          avisoLogin = _erroLogin(e);
          voltarParaSenha(manterAviso: true);
        } finally {
          _concluindo = false;
        }
      } else if (qrStatus == 'expired') {
        _pararQr();
      }
    } on ApiErro catch (e) {
      if (e.semRede) return;   // tenta na próxima volta
      _pararQr();
      _erroLogin(e);
    }
  }

  void _pararQr() {
    _tQr?.cancel();
    _tQr = null;
  }

  /* ======================= login: comum ======================= */

  /// "Voltar" / "Não sou eu": descarta o login em andamento.
  void voltarParaSenha({bool manterAviso = false}) {
    final t = ticket;
    if (t != null) unawaited(api.post('$_p/login/cancelar', {'ticket': t}).catchError((_) => null));
    _limparLogin();
    if (!manterAviso) avisoLogin = null;
    etapa = EtapaLogin.senha;
    notifyListeners();
  }

  void _limparLogin() {
    ticket = null;
    passo = {};
    restamTentativas = 5;
    celularStatus = null;
    _tCelular?.cancel();
    _pararQr();
    qr = null;
  }

  /// Resposta do servidor a qualquer passo do login: ou abriu a sessão, ou diz a etapa seguinte.
  Future<String?> _respostaLogin(Map r) async {
    if ((r['etapa'] ?? '') == 'pronto' && (r['token'] ?? '').toString().startsWith('nnconv_')) {
      api.token = r['token'].toString();
      await arm.gravarToken(api.token);
      _limparLogin();
      etapa = EtapaLogin.senha;
      avisoLogin = null;
      _aplicarEu((r['eu'] as Map).cast<String, dynamic>());
      _ir(Fase.pronto);
      _ligarCiclos();
      unawaited(verComunicados());
      return null;
    }
    if ((r['ticket'] ?? '').toString().isNotEmpty) ticket = r['ticket'].toString();
    passo = ((r['passo'] as Map?) ?? const {}).cast<String, dynamic>();
    restamTentativas = (r['restam_tentativas'] as num?)?.toInt() ?? 5;
    etapa = switch ((r['etapa'] ?? '').toString()) {
      'politica' => EtapaLogin.politica,
      'setup' => EtapaLogin.setup,
      _ => EtapaLogin.doisFatores,
    };
    celularStatus = null;
    notifyListeners();
    return null;
  }

  /// Erro de um passo do login: devolve o texto para a tela (ou volta ao começo).
  String? _erroLogin(ApiErro e) {
    if (e.codigo == 'ticket_invalido') {
      avisoLogin = e.mensagem;
      _limparLogin();
      etapa = EtapaLogin.senha;
      notifyListeners();
      return e.mensagem;
    }
    if (e.codigo == 'app_desligado' || e.codigo == 'app_indisponivel') {
      _bloquear(e);
      return null;
    }
    return e.mensagem;
  }

  void _irParaLogin({String? aviso}) {
    _limparLogin();
    etapa = EtapaLogin.senha;
    avisoLogin = aviso;
    _ir(Fase.login);
  }

  /* ======================= sessão ======================= */

  Future<void> sair() async {
    try {
      await api.post('$_p/logout');
    } catch (_) {
      // sai mesmo sem o servidor
    }
    await _encerrarSessao();
    _irParaLogin();
  }

  Future<void> _entrarComSessao() async {
    try {
      final r = await api.get('$_p/eu') as Map;
      _aplicarEu(r.cast<String, dynamic>());
      _ir(Fase.pronto);
      _ligarCiclos();
      unawaited(verComunicados());
    } on ApiErro catch (e) {
      if (e.sessaoAcabou) {
        await _encerrarSessao();
        _irParaLogin(aviso: e.mensagem);
        return;
      }
      _bloquear(e);
    }
  }

  Future<void> _encerrarSessao() async {
    _pararCiclos();
    api.token = null;
    await arm.gravarToken(null);
    eu = null;
    comunicados = [];
    naoLidas = 0;
  }

  void _perdeuAcesso(ApiErro e) {
    if (e.sessaoAcabou && fase == Fase.pronto) {
      unawaited(_encerrarSessao().then((_) => _irParaLogin(aviso: e.mensagem)));
    }
  }

  /* ======================= ciclos ======================= */

  void _ligarCiclos() {
    _pararCiclos();
    _tComunicados = Timer.periodic(AppConfig.cicloComunicados, (_) => verComunicados());
    _tEu = Timer.periodic(AppConfig.cicloEu, (_) => atualizarEu());
    _tAparencia = Timer.periodic(AppConfig.cicloAparencia, (_) => _carregarAparencia());
  }

  void _pararCiclos() {
    _tComunicados?.cancel();
    _tEu?.cancel();
    _tAparencia?.cancel();
  }

  /// Chamado ao voltar da bandeja: tudo de novo, na hora.
  Future<void> acordou() async {
    if (fase != Fase.pronto) return;
    await Future.wait([_carregarAparencia(), atualizarEu(), verComunicados()]);
  }

  Future<void> atualizarEu() async {
    if (fase != Fase.pronto || _carregandoEu) return;
    _carregandoEu = true;
    try {
      final r = await api.get('$_p/eu') as Map;
      final antes = naoLidas;
      _aplicarEu(r.cast<String, dynamic>());
      if (naoLidas > antes) await aoChegarMensagem?.call(antes, naoLidas);
      notifyListeners();
    } catch (_) {
      // a próxima volta tenta de novo
    } finally {
      _carregandoEu = false;
    }
  }

  /// Contador de não lidas vindo da tela de conversas (que consulta mais rápido).
  void definirNaoLidas(int n) {
    if (n == naoLidas) return;
    naoLidas = n;
    notifyListeners();
  }

  Future<void> verComunicados() async {
    if (fase != Fase.pronto) return;
    try {
      final r = (await api.get('$_p/comunicados/pendentes') as List).cast<Map>().map((m) => m.cast<String, dynamic>()).toList();
      final novos = r.where((c) => !_comunicadosVistos.contains((c['id'] as num).toInt())).toList();
      comunicados = r;
      for (final c in r) {
        _comunicadosVistos.add((c['id'] as num).toInt());
      }
      if (novos.isNotEmpty) await aoChegarComunicado?.call(novos);
      notifyListeners();
    } catch (_) {
      // sem rede: a próxima volta tenta
    }
  }

  /// "Entendi": registra no servidor e tira da fila.
  Future<void> comunicadoVisto(int id) async {
    comunicados = comunicados.where((c) => (c['id'] as num).toInt() != id).toList();
    notifyListeners();
    try {
      await api.post('$_p/comunicados/visto', {'id': id});
    } catch (_) {
      // volta na próxima consulta, se o servidor não registrou
      _comunicadosVistos.remove(id);
    }
  }

  Future<void> definirModo(String novo) async {
    if (novo == modo) return;
    final antes = modo;
    modo = novo;
    notifyListeners();
    aoMudarVisual?.call();
    try {
      await api.post('$_p/tema', {'modo': novo});
    } catch (_) {
      modo = antes;   // não gravou: a tela não pode ficar num modo e o site em outro
      notifyListeners();
      aoMudarVisual?.call();
    }
  }

  Future<void> _carregarAparencia() async {
    try {
      final r = (await api.get('$_p/aparencia') as Map).cast<String, dynamic>();
      if (r['versao'] != aparencia?['versao']) {
        aparencia = r;
        notifyListeners();
        aoMudarVisual?.call();
      }
    } catch (_) {
      // mantém o visual que já tinha
    }
  }

  void _aplicarEu(Map<String, dynamic> r) {
    eu = r;
    naoLidas = (r['nao_lidas'] as num?)?.toInt() ?? 0;
    final m = (r['modo'] ?? 'claro').toString();
    if (m != modo) {
      modo = m == 'escuro' ? 'escuro' : 'claro';
      aoMudarVisual?.call();
    }
  }

  void _bloquear(ApiErro e) {
    motivo = e.semRede ? 'Sem conexão com o servidor do NN Conecta. Confira a internet deste computador.' : e.mensagem;
    codigoBloqueio = e.semRede ? 'sem_rede' : e.codigo;
    _pararCiclos();
    _limparLogin();
    _ir(Fase.bloqueado);
  }

  /// "Tentar de novo" da tela de bloqueio.
  Future<void> tentarDeNovo() async {
    motivo = null;
    codigoBloqueio = null;
    _ir(Fase.iniciando);
    await iniciar();
  }

  void _ir(Fase f) {
    fase = f;
    notifyListeners();
  }

  static String _nomeDoComputador() {
    try {
      final h = Platform.localHostname;
      return h.replaceAll(RegExp(r'\.local$'), '');
    } catch (_) {
      return 'Computador';
    }
  }

  @override
  void dispose() {
    _tCelular?.cancel();
    _pararQr();
    _pararCiclos();
    super.dispose();
  }
}
