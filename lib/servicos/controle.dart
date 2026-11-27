// O estado do aplicativo: computador → login → sessão.
//
//   computador  sem chave, pendente, recusado ou revogado: a tela do código
//   login       computador autorizado, sem sessão
//   pronto      logado: as consultas periódicas rodam (comunicados mesmo com a
//               janela na bandeja)
//   bloqueado   fora da rede liberada, app desligado ou servidor fora do ar
//
// ⚠️ A chave do computador e o token ficam no chaveiro do sistema. Perder a
// sessão (expirou, encerrada pelo administrador) volta ao login; perder o
// computador (revogado) volta à tela do código.
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../api/cliente.dart';
import '../config.dart';
import 'alertas.dart';
import 'armazenamento.dart';

enum Fase { iniciando, computador, login, pronto, bloqueado }

class Controle extends ChangeNotifier {
  final Armazenamento arm;
  final Api api;
  Controle(this.arm, {Api? api})
      : api = api ?? Api(),
        alertas = Alertas(arm) {
    this.api.aoPerderAcesso = _perdeuAcesso;
  }

  /// Os avisos de mensagem nova (quadro no canto, notificação, som).
  final Alertas alertas;

  Fase fase = Fase.iniciando;
  String? motivo;           // texto da tela de bloqueio / do computador recusado
  String? codigoBloqueio;   // `error.code` do bloqueio (ip_bloqueado, app_desligado…)

  // Computador
  String? statusComputador; // pendente | aprovado | recusado | revogado
  String? codigo;
  String nomeComputador = '';

  // Sessão
  Map<String, dynamic>? aparencia;
  Map<String, dynamic>? eu;
  String modo = 'claro';
  int naoLidas = 0;
  List<Map<String, dynamic>> comunicados = [];
  final Set<int> _comunicadosVistos = {};

  /// A janela está à vista? (fora da bandeja). Quem decide os avisos de mensagem
  /// é `alertas.janelaEmFoco`, que olha também o foco.
  bool janelaVisivel = true;

  /// Aviso de comunicado para a casca (janela, som, notificação) — ligado no `main`.
  /// (Mensagem nova não passa por aqui: é `alertas`, alimentado pela lista e pela
  /// conversa aberta.)
  Future<void> Function(List<Map<String, dynamic>> novos)? aoChegarComunicado;
  void Function()? aoMudarVisual;

  Timer? _tCodigo, _tComunicados, _tEu, _tAparencia;
  bool _carregandoEu = false;

  bool get escuro => modo == 'escuro';
  String get primeiroNome => (eu?['primeiro'] ?? '').toString();
  int get meuId => (eu?['id'] as num?)?.toInt() ?? 0;

  /* ======================= início ======================= */

  Future<void> iniciar() async {
    api.chave = await arm.chaveComputador();
    api.token = await arm.token();
    nomeComputador = _nomeDoComputador();
    if (api.chave == null) {
      _ir(Fase.computador);
      return;
    }
    await conferirComputador();
  }

  /// Consulta o estado do computador e decide a tela.
  Future<void> conferirComputador() async {
    try {
      final r = await api.get('/v1/callapp/computador') as Map;
      statusComputador = r['status']?.toString();
      codigo = r['codigo']?.toString();
      if ((r['nome'] ?? '').toString().isNotEmpty) nomeComputador = r['nome'].toString();
      motivo = r['motivo']?.toString();
      if (statusComputador == 'aprovado') {
        _tCodigo?.cancel();
        await _carregarAparencia();
        if (api.token != null) {
          await _entrar();
        } else {
          _ir(Fase.login);
        }
      } else {
        _ir(Fase.computador);
        if (statusComputador == 'pendente') _vigiarCodigo();
      }
    } on ApiErro catch (e) {
      if (e.codigo == 'computador_desconhecido') {
        // A chave guardada não existe mais no servidor (pedido antigo apagado).
        await arm.gravarChaveComputador(null);
        api.chave = null;
        statusComputador = null;
        _ir(Fase.computador);
        return;
      }
      _bloquear(e);
    }
  }

  /// "Pedir autorização": registra este computador e mostra o código.
  Future<String?> pedirAutorizacao() async {
    try {
      api.chave = null;
      api.token = null;
      final r = await api.post('/v1/callapp/computador', {'so': AppConfig.so, 'nome': nomeComputador, 'versao': AppConfig.versao}) as Map;
      api.chave = r['chave'].toString();
      await arm.gravarChaveComputador(api.chave);
      await arm.gravarToken(null);
      statusComputador = 'pendente';
      codigo = r['codigo']?.toString();
      motivo = null;
      _ir(Fase.computador);
      _vigiarCodigo();
      return null;
    } on ApiErro catch (e) {
      if (e.codigo == 'ip_bloqueado' || e.codigo == 'app_desligado' || e.codigo == 'app_indisponivel') {
        _bloquear(e);
        return null;
      }
      return e.mensagem;
    }
  }

  void _vigiarCodigo() {
    _tCodigo?.cancel();
    _tCodigo = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (statusComputador != 'pendente') {
        _tCodigo?.cancel();
        return;
      }
      await conferirComputador();
    });
  }

  /* ======================= login ======================= */

  Future<String?> entrar(String email, String senha) async {
    try {
      final r = await api.post('/v1/callapp/login', {'email': email.trim(), 'senha': senha}) as Map;
      api.token = r['token'].toString();
      await arm.gravarToken(api.token);
      _aplicarEu((r['eu'] as Map).cast<String, dynamic>());
      _ir(Fase.pronto);
      _ligarCiclos();
      unawaited(verComunicados());
      return null;
    } on ApiErro catch (e) {
      if (e.computadorFora) {
        await conferirComputador();
        return null;
      }
      if (e.codigo == 'ip_bloqueado' || e.codigo == 'app_desligado') {
        _bloquear(e);
        return null;
      }
      return e.mensagem;
    }
  }

  Future<void> sair() async {
    try {
      await api.post('/v1/callapp/logout');
    } catch (_) {
      // sai mesmo sem o servidor
    }
    await _encerrarSessao();
    _ir(Fase.login);
  }

  Future<void> _entrar() async {
    try {
      final r = await api.get('/v1/callapp/eu') as Map;
      _aplicarEu(r.cast<String, dynamic>());
      _ir(Fase.pronto);
      _ligarCiclos();
      unawaited(verComunicados());
    } on ApiErro catch (e) {
      if (e.sessaoAcabou) return;      // `_perdeuAcesso` já levou ao login
      if (e.computadorFora) return;
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
    alertas.limpar();
  }

  void _perdeuAcesso(ApiErro e) {
    if (e.sessaoAcabou && fase == Fase.pronto) {
      motivo = e.mensagem;
      unawaited(_encerrarSessao().then((_) => _ir(Fase.login)));
    } else if (e.computadorFora && fase != Fase.computador) {
      unawaited(_encerrarSessao().then((_) => conferirComputador()));
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
      final r = await api.get('/v1/callapp/eu') as Map;
      _aplicarEu(r.cast<String, dynamic>());
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
      final r = (await api.get('/v1/callapp/comunicados/pendentes') as List).cast<Map>().map((m) => m.cast<String, dynamic>()).toList();
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
      await api.post('/v1/callapp/comunicados/visto', {'id': id});
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
      await api.post('/v1/callapp/tema', {'modo': novo});
    } catch (_) {
      modo = antes;   // não gravou: a tela não pode ficar num modo e o site em outro
      notifyListeners();
      aoMudarVisual?.call();
    }
  }

  Future<void> _carregarAparencia() async {
    try {
      final r = (await api.get('/v1/callapp/aparencia') as Map).cast<String, dynamic>();
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
    alertas.naoPerturbe = ((r['status'] as Map?)?['escolhido'] ?? '') == 'nao_perturbe';
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
    _tCodigo?.cancel();
    _pararCiclos();
    super.dispose();
  }
}
