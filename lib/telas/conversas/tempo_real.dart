// Tempo real (Soketi, protocolo Pusher) — só um EMPURRÃO.
//
// Com o tempo real ligado no servidor, o app assina o canal da conversa aberta
// (`private-im-conv-<id>`, autorizado em `/socket-auth`, que confere se a pessoa
// é membro) e, a cada evento (message, edited, reaction, read), consulta de
// novo na hora. Os eventos saem no formato do SITE, então o app nunca os
// desenha: quem desenha é a consulta (`?after=`), que continua rodando de
// reserva — com o WebSocket caído, nada se perde, só fica mais lento.
import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'chat_api.dart';

class TempoReal {
  final ChatApi chat;
  TempoReal(this.chat);

  WebSocketChannel? _ws;
  StreamSubscription? _sub;
  String? _socketId;
  String? _canal;            // o canal assinado agora
  int? _conversa;            // a conversa que se quer ouvir
  Timer? _religar, _ping;
  int _espera = 2;
  bool _ligado = false, _encerrado = false;
  Map<String, dynamic>? _cfg;

  /// Chamado a cada evento da conversa ouvida.
  void Function(String evento)? aoEvento;

  bool get conectado => _socketId != null;

  Future<void> iniciar() async {
    if (_ligado) return;
    _ligado = true;
    try {
      _cfg = await chat.socket();
    } catch (_) {
      _cfg = null;
    }
    if (_cfg?['enabled'] != true) return;
    _conectar();
  }

  void _conectar() {
    if (_encerrado || _cfg == null) return;
    final c = _cfg!;
    final tls = c['forceTLS'] != false;
    final porta = (c['port'] as num?)?.toInt() ?? (tls ? 443 : 80);
    final host = (c['host'] ?? '').toString();
    final chave = (c['key'] ?? '').toString();
    if (host.isEmpty || chave.isEmpty) return;
    final u = Uri(scheme: tls ? 'wss' : 'ws', host: host, port: porta, path: '/app/$chave',
        queryParameters: {'protocol': '7', 'client': 'nn-conversas', 'version': '1.0'});
    try {
      _ws = WebSocketChannel.connect(u);
      _sub = _ws!.stream.listen(_receber, onDone: _caiu, onError: (_) => _caiu(), cancelOnError: true);
    } catch (_) {
      _caiu();
    }
  }

  void _receber(dynamic bruto) {
    Map<String, dynamic> m;
    try {
      m = (jsonDecode(bruto.toString()) as Map).cast<String, dynamic>();
    } catch (_) {
      return;
    }
    final ev = (m['event'] ?? '').toString();
    if (ev == 'pusher:connection_established') {
      try {
        final d = jsonDecode(m['data'].toString()) as Map;
        _socketId = d['socket_id']?.toString();
        final t = (d['activity_timeout'] as num?)?.toInt() ?? 120;
        _ping?.cancel();
        _ping = Timer.periodic(Duration(seconds: t > 10 ? t - 5 : 30), (_) => _enviar({'event': 'pusher:ping', 'data': {}}));
      } catch (_) {}
      _espera = 2;
      _canal = null;
      unawaited(_assinar());
      return;
    }
    if (ev == 'pusher:ping') {
      _enviar({'event': 'pusher:pong', 'data': {}});
      return;
    }
    if (ev.startsWith('pusher')) return;
    if (m['channel'] != null && m['channel'] == _canal) aoEvento?.call(ev);
  }

  void _enviar(Map<String, dynamic> m) {
    try {
      _ws?.sink.add(jsonEncode(m));
    } catch (_) {}
  }

  /// Troca o canal ouvido (abrir outra conversa). `null` = nenhum.
  Future<void> ouvir(int? conversa) async {
    _conversa = conversa;
    await _assinar();
  }

  Future<void> _assinar() async {
    final sid = _socketId;
    if (sid == null) return;
    final novo = _conversa == null ? null : 'private-im-conv-$_conversa';
    if (novo == _canal) return;
    if (_canal != null) _enviar({'event': 'pusher:unsubscribe', 'data': {'channel': _canal}});
    _canal = null;
    if (novo == null) return;
    try {
      final auth = await chat.socketAuth(sid, novo);
      if (_socketId != sid || _conversa == null || 'private-im-conv-$_conversa' != novo) return;
      _enviar({'event': 'pusher:subscribe', 'data': {'auth': auth, 'channel': novo}});
      _canal = novo;
    } catch (_) {
      // sem tempo real nesta conversa: a consulta de reserva segue
    }
  }

  void _caiu() {
    _socketId = null;
    _canal = null;
    _ping?.cancel();
    _sub?.cancel();
    _sub = null;
    _ws = null;
    if (_encerrado) return;
    _religar?.cancel();
    _religar = Timer(Duration(seconds: _espera), _conectar);
    _espera = (_espera * 2).clamp(2, 120);
  }

  void encerrar() {
    _encerrado = true;
    _religar?.cancel();
    _ping?.cancel();
    _sub?.cancel();
    try {
      _ws?.sink.close();
    } catch (_) {}
  }
}
