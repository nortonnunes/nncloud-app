// A conexão que cai sem resposta — o "Connection closed before full header was
// received" que o Windows mostrava quando o app reaproveitava uma conexão que o
// servidor (keep-alive de 5 s) já tinha fechado.
//
// O servidor aqui é um socket cru: ele decide, pedido a pedido, se responde ou
// derruba a conexão sem mandar nada.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:nncloud_motor/src/api.dart';
import 'package:test/test.dart';

class ServidorFalso {
  late final ServerSocket _s;
  int conexoes = 0;
  final pedidos = <String>[];   // "MÉTODO caminho" na ordem em que chegaram
  int derrubar = 0;              // quantos dos próximos pedidos derrubar sem responder

  Future<void> iniciar() async {
    _s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _s.listen(_atender);
  }

  String get base => 'http://127.0.0.1:${_s.port}';

  Future<void> parar() => _s.close();

  void _atender(Socket sock) {
    conexoes++;
    var buf = <int>[];
    sock.listen((dados) {
      buf.addAll(dados);
      while (true) {
        final txt = latin1.decode(buf, allowInvalid: true);
        final fim = txt.indexOf('\r\n\r\n');
        if (fim < 0) return;
        final cab = txt.substring(0, fim);
        final m = RegExp(r'content-length:\s*(\d+)', caseSensitive: false).firstMatch(cab);
        final n = m == null ? 0 : int.parse(m.group(1)!);
        if (buf.length < fim + 4 + n) return;
        buf = buf.sublist(fim + 4 + n);
        final linha = cab.split('\r\n').first.split(' ');
        pedidos.add('${linha[0]} ${Uri.parse(linha[1]).path}');
        if (derrubar > 0) {
          derrubar--;
          sock.destroy();
          return;
        }
        final corpo = utf8.encode(jsonEncode({'data': {'ok': true, 'pares': [], 'espacos': [], 'ancora': 'a1'}}));
        sock.add(latin1.encode('HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: ${corpo.length}\r\n'
            'Connection: keep-alive\r\n\r\n'));
        sock.add(corpo);
      }
    }, onError: (_) {}, cancelOnError: true);
  }
}

void main() {
  late ServidorFalso srv;
  late Api api;

  setUp(() async {
    srv = ServidorFalso();
    await srv.iniciar();
    api = Api(srv.base, token: 'nncl_teste')..esperasRepeticao = const [Duration(milliseconds: 10), Duration(milliseconds: 10)];
  });

  tearDown(() async {
    api.fechar();
    await srv.parar();
  });

  test('o cliente não guarda conexão parada por mais tempo que o servidor (5 s)', () {
    final h = HttpClient();
    Api('http://x', http: h);
    expect(h.idleTimeout, lessThan(const Duration(seconds: 5)));
    h.close(force: true);
  });

  test('GET com a conexão caindo uma vez: repete e funciona', () async {
    srv.derrubar = 1;
    final r = await api.eu();
    expect(r['ok'], isTrue);
    expect(srv.pedidos, ['GET /v1/cloud/eu', 'GET /v1/cloud/eu']);
  });

  test('GET com a conexão caindo duas vezes seguidas: ainda funciona na terceira', () async {
    srv.derrubar = 2;
    await api.espacos();
    expect(srv.pedidos.length, 3);
  });

  test('queda em todas as tentativas: erro de rede (vira "offline" no ciclo), sem repetir para sempre', () async {
    srv.derrubar = 99;
    await expectLater(api.eu(), throwsA(isA<ApiErro>().having((e) => e.queda, 'queda', isTrue).having((e) => e.transitorio, 'transitorio', isTrue)));
    expect(srv.pedidos.length, 3);
  });

  test('POST que pode repetir (mudanças, garantir, gravar base, fp/mudanças): repete', () async {
    srv.derrubar = 1;
    await api.mudancas([{'par': 1, 'cursor': 0}]);
    srv.derrubar = 1;
    await api.garantir(espacoId: 1, caminhos: ['a/b']);
    srv.derrubar = 1;
    await api.gravarBase(1, [], []);
    srv.derrubar = 1;
    await api.fpMudancas('x');
    expect(srv.pedidos.where((p) => p.startsWith('POST')).length, 8);
  });

  test('POST que NÃO pode repetir (criar pasta, iniciar e concluir envio, token): falha sem mandar de novo', () async {
    for (final f in <Future<dynamic> Function()>[
      () => api.criarPasta(espacoId: 1, nome: 'x'),
      () => api.iniciarEnvio({'tamanho': 1}),
      () => api.concluirEnvio('e1'),
      () => api.buscarToken('s'),
    ]) {
      srv.pedidos.clear();
      srv.derrubar = 1;
      await expectLater(f(), throwsA(isA<ApiErro>().having((e) => e.queda, 'queda', isTrue)));
      expect(srv.pedidos.length, 1, reason: 'mandou de novo um pedido que cria algo');
    }
  });

  test('resposta de erro do servidor (500) não é tratada como queda e não é repetida aqui', () async {
    final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var n = 0;
    s.listen((r) {
      n++;
      r.response
        ..statusCode = 500
        ..write(jsonEncode({'error': {'status': 500, 'message': 'falhou'}}))
        ..close();
    });
    final a = Api('http://127.0.0.1:${s.port}');
    await expectLater(a.eu(), throwsA(isA<ApiErro>().having((e) => e.status, 'status', 500).having((e) => e.queda, 'queda', isFalse)));
    expect(n, 1);
    a.fechar();
    await s.close(force: true);
  });

  test('conexão parada além do limite não é reaproveitada (abre outra)', () async {
    await api.eu();
    await Future<void>.delayed(Api.ociosoMax + const Duration(milliseconds: 600));
    await api.eu();
    expect(srv.conexoes, 2);
  }, timeout: const Timeout(Duration(seconds: 15)));

  // Desempenho, não correção: confere que o keep-alive continua ligado. O cliente
  // do Dart só devolve a conexão ao estoque DEPOIS de terminar a resposta; um
  // pedido colado no anterior pode chegar antes disso e abrir outra — por isso a
  // pausa curta (bem abaixo de `Api.ociosoMax`). Mesmo assim roda só no Mac: nas
  // máquinas do GitHub (Windows e Linux) o momento varia e ele falhou nas duas,
  // travando a compilação. O que corrige de verdade — não reusar conexão parada
  // além de `Api.ociosoMax` e repetir as quedas — é testado acima, em todo lugar.
  test('pedidos seguidos dentro do limite reaproveitam a mesma conexão', () async {
    const pausa = Duration(milliseconds: 100);
    await api.eu();
    await Future<void>.delayed(pausa);
    await api.eu();
    await Future<void>.delayed(pausa);
    await api.eu();
    expect(srv.conexoes, 1);
  }, testOn: 'mac-os');
}
