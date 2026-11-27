// As reuniões do Google Meet no app: o modelo (estado pelo relógio, link do
// Meet conferido), o cartão nos quatro estados e o diálogo de criar.
//   flutter test test/reuniao_test.dart --update-goldens   → gera os PNG
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nn_conversas/api/cliente.dart';
import 'package:nn_conversas/telas/conversas/chat_api.dart';
import 'package:nn_conversas/telas/conversas/dialogos.dart';
import 'package:nn_conversas/telas/conversas/mensagem.dart';

import 'telas_test.dart' show app, controleFalso, fontes, reuniaoFalsa;

Reuniao r(Map<String, dynamic> m) => Reuniao.de(m)!;

void main() {
  setUpAll(() async {
    await fontes();
    await initializeDateFormatting('pt_BR');
  });

  group('modelo', () {
    test('estado pelo relógio: agendada, agora (5 min antes), encerrada, cancelada', () {
      final base = DateTime(2026, 11, 26, 14);
      final ini = base.millisecondsSinceEpoch ~/ 1000;
      Reuniao com(String estado) => r({'id': 1, 'inicio_ts': ini, 'fim_ts': ini + 1800, 'estado': estado, 'url': ''});
      expect(com('agendada').estado(base.subtract(const Duration(minutes: 6))), 'agendada');
      expect(com('agendada').estado(base.subtract(const Duration(minutes: 5))), 'agora');
      expect(com('agendada').estado(base.add(const Duration(minutes: 29))), 'agora');
      expect(com('agora').estado(base.add(const Duration(minutes: 30))), 'encerrada');
      expect(com('cancelada').estado(base), 'cancelada');
      expect(com('cancelada').viva(base), isFalse);
    });

    test('Entrar só com o link do Meet', () {
      Reuniao com(String url) => r({'id': 1, 'url': url});
      expect(com('https://meet.google.com/abc-defg-hij').urlOk, isTrue);
      expect(com('http://meet.google.com/abc').urlOk, isFalse);
      expect(com('https://meet.google.com.evil.com/abc').urlOk, isFalse);
      expect(com('javascript:alert(1)').urlOk, isFalse);
      expect(com('https://meet.google.com/a/../b').urlOk, isFalse);
    });

    test('quem cancela: quem criou ou quem o servidor liberou', () {
      expect(r({'id': 1, 'autor_id': 7}).podeCancelarPor(7), isTrue);
      expect(r({'id': 1, 'autor_id': 7}).podeCancelarPor(8), isFalse);
      expect(r({'id': 1, 'autor_id': 7, 'pode_cancelar': true}).podeCancelarPor(8), isTrue);
      expect(r({'id': 1, 'autor_id': 0}).podeCancelarPor(0), isFalse);
    });

    test('a mensagem com reunião não se edita e lê o "meet"', () {
      final m = Mensagem.de({
        'id': 9, 'user_id': 1, 'user_name': 'Ana', 'mine': true, 'body': '📹 X', 'at': '26/11/2026 10:00',
        'ts': DateTime.now().millisecondsSinceEpoch ~/ 1000, 'can_edit': true,
        'meet': reuniaoFalsa(1, 'X', 'Hoje, 10:00–10:30', inicio: 0),
      });
      expect(m.reuniao?.titulo, 'X');
      expect(m.aindaEditavel, isFalse);
      expect(Reuniao.de(null), isNull);
      expect(Reuniao.de({'id': 0}), isNull);
    });

    test('rótulo da duração', () {
      expect(duracoesReuniao.map(rotuloDuracao).toList(), ['15 min', '30 min', '45 min', '1 h', '1,5 h', '2 h', '3 h', '4 h']);
    });
  });

  for (final b in [Brightness.light, Brightness.dark]) {
    final sufixo = b == Brightness.dark ? '_escuro' : '';
    testWidgets('cartões nos quatro estados$sufixo', (t) async {
      t.view.physicalSize = const Size(900, 760);
      t.view.devicePixelRatio = 1;
      final c = await controleFalso(Directory.systemTemp.createTempSync('reu'));
      var cancelou = 0;
      final cartoes = [
        r(reuniaoFalsa(1, 'Reunião com Bruno Lima', 'Hoje, 10:44–11:14', inicio: -60, podeCancelar: true)),
        r(reuniaoFalsa(2, 'Alinhamento da carteira Unimed', 'Amanhã, 09:00–10:00', inicio: 86400, duracao: 60, autor: 2, descricao: 'Pauta: metas de dezembro')),
        r(reuniaoFalsa(3, 'Retorno do cliente', 'Hoje, 08:00–08:30', inicio: -7200)),
        r(reuniaoFalsa(4, 'Planejamento', 'Amanhã, 15:00–16:00', inicio: 86400, estado: 'cancelada')),
      ];
      await t.pumpWidget(app(c, b, Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: Wrap(spacing: 16, runSpacing: 16, children: [
            for (final x in cartoes) CartaoReuniao(x, meuId: 1, aoCancelar: () => cancelou++),
          ]),
        ),
      )));
      await t.pump();
      // Agora: Entrar + Agenda + Cancelar (é da Ana). Agendada de outro: sem Cancelar.
      expect(find.text('Acontecendo agora'), findsOneWidget);
      expect(find.text('Agendada'), findsOneWidget);
      expect(find.text('Encerrada'), findsOneWidget);
      expect(find.text('Cancelada'), findsOneWidget);
      expect(find.text('Entrar'), findsNWidgets(2));
      expect(find.text('Cancelar reunião'), findsOneWidget);
      await t.tap(find.text('Cancelar reunião'));
      expect(cancelou, 1);
      await t.pumpAndSettle();
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/reunioes$sufixo.png'));
      await t.pumpWidget(const SizedBox());
      t.view.reset();
    });
  }

  /// API falsa só das reuniões, guardando o que o app mandou.
  ({http.Client cliente, List<Map<String, dynamic>> enviados}) apiReunioes({bool pode = true, bool conectado = true, int statusCriar = 201}) {
    final enviados = <Map<String, dynamic>>[];
    final cli = MockClient((req) async {
      http.Response json(Object d, [int st = 200]) => http.Response(jsonEncode(st >= 400 ? d : {'data': d}), st, headers: {'content-type': 'application/json; charset=utf-8'});
      if (req.url.path.endsWith('/meet/google')) {
        return json({'disponivel': true, 'configurado': true, 'conectado': conectado, 'pode_criar': pode, 'email': 'ana@gmail.test', 'conectar_url': 'https://nnconecta.com/perfil?tab=integracoes'});
      }
      if (req.url.path.endsWith('/conversations/5/meet')) {
        enviados.add((jsonDecode(req.body) as Map).cast<String, dynamic>());
        if (statusCriar == 428) {
          return json({'error': {'status': 428, 'message': 'Falta a permissão para criar reuniões: conecte o Google de novo em Perfil → Integrações.'}}, 428);
        }
        return json({'nova': true, 'meet': reuniaoFalsa(9, 'Pauta', 'Amanhã, 10:00–11:00', inicio: 86400, duracao: 60), 'message': null}, statusCriar);
      }
      return json({});
    });
    return (cliente: cli, enviados: enviados);
  }

  Future<void> abrir(WidgetTester t, Brightness b, ChatApi chat, void Function((Reuniao?, Mensagem?)?) fim) async {
    final c = await controleFalso(Directory.systemTemp.createTempSync('reud'));
    await t.pumpWidget(app(c, b, Builder(builder: (ctx) => Scaffold(
      body: Center(child: FilledButton(onPressed: () async => fim(await novaReuniao(ctx, chat, 5, tituloPadrao: 'Reunião com Bruno Lima')), child: const Text('abrir'))),
    ))));
    await t.tap(find.text('abrir'));
    await t.pump();
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await t.pump();
  }

  for (final b in [Brightness.light, Brightness.dark]) {
    final sufixo = b == Brightness.dark ? '_escuro' : '';
    testWidgets('diálogo: agendar manda data, hora, duração e convidar$sufixo', (t) async {
      t.view.physicalSize = const Size(900, 900);
      t.view.devicePixelRatio = 1;
      final api = apiReunioes();
      (Reuniao?, Mensagem?)? fim;
      await abrir(t, b, ChatApi(Api(base: 'http://teste', token: 'nnconv_y', cliente: api.cliente)), (r) => fim = r);
      expect(find.text('Iniciar reunião'), findsOneWidget);
      expect(find.byIcon(Icons.calendar_today_outlined), findsNothing);
      await t.tap(find.text('Agendar'));
      await t.pump();
      expect(find.text('Agendar reunião'), findsOneWidget);
      expect(find.text('1 h'), findsOneWidget); // agendar começa com 1 h
      await t.enterText(find.widgetWithText(TextField, 'Título'), 'Pauta');
      FocusManager.instance.primaryFocus?.unfocus();
      await t.pumpAndSettle();
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/reuniao_dialogo$sufixo.png'));
      await t.tap(find.text('Agendar reunião'));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await t.pumpAndSettle();
      expect(api.enviados, hasLength(1));
      final e = api.enviados.first;
      expect(e['modo'], 'agendar');
      expect(e['titulo'], 'Pauta');
      expect(e['duracao'], 60);
      expect(e['convidar'], true);
      expect(e['data'], matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
      expect(e['hora'], matches(RegExp(r'^\d{2}:00$')));
      expect(fim?.$1?.titulo, 'Pauta');
      expect(find.byType(AlertDialog), findsNothing);
      await t.pumpWidget(const SizedBox());
      t.view.reset();
    });
  }

  testWidgets('diálogo: Google só para ler → aviso, envio travado', (t) async {
    t.view.physicalSize = const Size(900, 900);
    t.view.devicePixelRatio = 1;
    final api = apiReunioes(pode: false, conectado: true);
    await abrir(t, Brightness.light, ChatApi(Api(base: 'http://teste', token: 'nnconv_y', cliente: api.cliente)), (_) {});
    expect(find.textContaining('só para ler a agenda'), findsOneWidget);
    expect(find.text('Conectar no NN Conecta'), findsOneWidget);
    final botao = t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Iniciar reunião'));
    expect(botao.onPressed, isNull);
    await t.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/reuniao_sem_google.png'));
    await t.pumpWidget(const SizedBox());
    t.view.reset();
  });

  testWidgets('diálogo: 428 do servidor vira o aviso de conectar, sem fechar', (t) async {
    t.view.physicalSize = const Size(900, 900);
    t.view.devicePixelRatio = 1;
    final api = apiReunioes(statusCriar: 428);
    await abrir(t, Brightness.light, ChatApi(Api(base: 'http://teste', token: 'nnconv_y', cliente: api.cliente)), (_) {});
    await t.tap(find.text('Agendar'));
    await t.pump();
    await t.tap(find.text('Agendar reunião'));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await t.pump();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('conecte o Google de novo'), findsOneWidget);
    expect(t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Agendar reunião')).onPressed, isNull);
    await t.pumpWidget(const SizedBox());
    t.view.reset();
  });
}
