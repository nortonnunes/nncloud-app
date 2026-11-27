// Os avisos de mensagem nova: quem recebe o quê (quadro no canto, notificação,
// som), sem repetir a mesma mensagem, e o desenho do quadro e da configuração.
//   flutter test test/alertas_test.dart --update-goldens
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nn_conversas/servicos/alertas.dart';
import 'package:nn_conversas/servicos/armazenamento.dart';
import 'package:nn_conversas/telas/aviso_mensagem.dart';
import 'package:nn_conversas/telas/conversas/chat_api.dart';

import 'telas_test.dart' show app, controleFalso, fontes;

ConversaLida _c(int id, int nao, {int ult = 0, String titulo = 'Bruno Lima', bool grupo = false, String autor = ''}) =>
    ConversaLida(id: id, naoLidas: nao, ultimoId: ult, titulo: titulo, grupo: grupo, autor: autor, previa: 'Oi, tudo bem?');

AvisoMensagem _a(int conv, {int ult = 0, int quantas = 1, String titulo = 'Bruno Lima'}) =>
    AvisoMensagem(conversa: conv, titulo: titulo, previa: 'Oi', ultimoId: ult, quantas: quantas);

/// Alertas com contadores no lugar do som e da notificação.
({Alertas al, List<AvisoMensagem> notif, List<int> som}) _novo() {
  final notif = <AvisoMensagem>[];
  final som = <int>[];
  final al = Alertas()
    ..tocarSom = (() async => som.add(1))
    ..mostrarNotificacao = ((a) async => notif.add(a));
  return (al: al, notif: notif, som: som);
}

void main() {
  group('DetectorConversas', () {
    test('a primeira leitura só guarda: abrir o app não dispara uma rajada', () {
      final d = DetectorConversas();
      expect(d.comparar([_c(1, 3), _c(2, 0)]), isEmpty);
    });

    test('mais não lidas = aviso, com quantas chegaram', () {
      final d = DetectorConversas()..comparar([_c(1, 1, ult: 10), _c(2, 0, ult: 5)]);
      final n = d.comparar([_c(1, 3, ult: 12), _c(2, 0, ult: 5)]);
      expect(n.map((a) => a.conversa), [1]);
      expect(n.first.quantas, 2);
      expect(n.first.ultimoId, 12);
    });

    test('leu uma e chegou outra entre as leituras: o id novo avisa', () {
      final d = DetectorConversas()..comparar([_c(1, 1, ult: 10)]);
      final n = d.comparar([_c(1, 1, ult: 11)]);
      expect(n.single.quantas, 1);
    });

    test('conversa nova (ou desarquivada) com não lidas = aviso; leu tudo = nada', () {
      final d = DetectorConversas()..comparar([_c(1, 2, ult: 10)]);
      expect(d.comparar([_c(1, 0, ult: 10)]), isEmpty);
      final n = d.comparar([_c(1, 0, ult: 10), _c(7, 1, ult: 40, titulo: 'Equipe TI', grupo: true, autor: 'Carla')]);
      expect(n.single.conversa, 7);
      expect(n.single.grupo, isTrue);
      expect(n.single.autor, 'Carla');
    });

    test('servidor antigo (sem last_id): só o aumento das não lidas avisa', () {
      final d = DetectorConversas()..comparar([_c(1, 1)]);
      expect(d.comparar([_c(1, 1)]), isEmpty);
      expect(d.comparar([_c(1, 2)]).single.quantas, 1);
    });
  });

  group('Alertas', () {
    test('app na frente, noutra conversa: quadro + som; sem notificação', () {
      final t = _novo();
      t.al.conversaNaTela = 5;
      expect(t.al.chegou(_a(1, ult: 10)), 'quadro');
      expect(t.al.quadros.value.single.conversa, 1);
      expect(t.notif, isEmpty);
      expect(t.som, hasLength(1));
    });

    test('a conversa que a pessoa está lendo não avisa', () {
      final t = _novo();
      t.al.conversaNaTela = 1;
      expect(t.al.olhando(1), isTrue);
      expect(t.al.chegou(_a(1, ult: 10)), 'nada');
      expect(t.som, isEmpty);
      expect(t.al.quadros.value, isEmpty);
    });

    test('minimizado ou atrás de outra janela: notificação + som (mesmo a conversa aberta)', () {
      final t = _novo();
      t.al
        ..conversaNaTela = 1
        ..janelaEmFoco = false;
      expect(t.al.olhando(1), isFalse);
      expect(t.al.chegou(_a(1, ult: 10)), 'notificacao');
      expect(t.notif.single.conversa, 1);
      expect(t.som, hasLength(1));
      expect(t.al.quadros.value, isEmpty);
    });

    test('a mesma mensagem pela lista e pela conversa aberta: um aviso só', () {
      final t = _novo();
      t.al.janelaEmFoco = false;
      t.al.chegou(_a(1, ult: 10), agora: DateTime(2026, 1, 1, 10));
      expect(t.al.chegou(_a(1, ult: 10), agora: DateTime(2026, 1, 1, 10, 0, 9)), 'nada');
      expect(t.notif, hasLength(1));
      expect(t.al.chegou(_a(1, ult: 11), agora: DateTime(2026, 1, 1, 10, 0, 20)), 'notificacao');
      expect(t.notif, hasLength(2));
    });

    test('rajada de várias conversas: o som toca uma vez', () {
      final t = _novo();
      final h = DateTime(2026, 1, 1, 10);
      t.al.chegou(_a(1, ult: 1), agora: h);
      t.al.chegou(_a(2, ult: 2), agora: h.add(const Duration(milliseconds: 300)));
      t.al.chegou(_a(3, ult: 3), agora: h.add(const Duration(milliseconds: 900)));
      expect(t.som, hasLength(1));
      t.al.chegou(_a(4, ult: 4), agora: h.add(const Duration(seconds: 3)));
      expect(t.som, hasLength(2));
      expect(t.al.quadros.value.length, Alertas.maxQuadros, reason: 'no máximo três empilhados');
      expect(t.al.quadros.value.first.conversa, 4, reason: 'o mais novo em cima');
    });

    test('mais mensagens da mesma conversa viram um quadro só', () {
      final t = _novo();
      t.al.chegou(_a(1, ult: 1));
      t.al.chegou(_a(2, ult: 2));
      t.al.chegou(_a(1, ult: 3, quantas: 2));
      expect(t.al.quadros.value.map((a) => a.conversa), [1, 2]);
      expect(t.al.quadros.value.first.quantas, 3);
      t.al.abriu(1);
      expect(t.al.quadros.value.map((a) => a.conversa), [2]);
    });

    test('Não perturbe: sem som e sem notificação; o quadro continua', () {
      final t = _novo();
      t.al.naoPerturbe = true;
      expect(t.al.chegou(_a(1, ult: 1)), 'quadro');
      t.al.janelaEmFoco = false;
      expect(t.al.chegou(_a(2, ult: 2)), 'nada');
      expect(t.som, isEmpty);
      expect(t.notif, isEmpty);
    });

    test('cada aviso pode ser desligado, e a escolha fica gravada no computador', () async {
      final dir = Directory.systemTemp.createTempSync('cc_alertas');
      final arm = Armazenamento();
      await arm.iniciar(base: dir);
      final al = Alertas(arm);
      expect([al.som, al.quadro, al.notificacao], [true, true, true]);
      al.definir(som: false, quadro: false);
      final outra = Alertas(arm);
      expect([outra.som, outra.quadro, outra.notificacao], [false, false, true]);
      final som = <int>[];
      outra.tocarSom = () async => som.add(1);
      expect(outra.chegou(_a(1, ult: 1)), 'nada', reason: 'quadro desligado');
      expect(som, isEmpty, reason: 'som desligado');
    });

    test('o som desligado na 1.0.0 continua desligado (mesma preferência)', () async {
      final dir = Directory.systemTemp.createTempSync('cc_alertas_som');
      final arm = Armazenamento();
      await arm.iniciar(base: dir);
      arm.definir('som_mensagem', false);
      expect(Alertas(arm).som, isFalse);
    });

    test('textos da notificação não levam o conteúdo da mensagem', () {
      const direta = AvisoMensagem(conversa: 1, titulo: 'Bruno Lima', previa: 'segredo', quantas: 1);
      expect(direta.tituloNotificacao, 'Bruno Lima');
      expect(direta.textoNotificacao, 'Enviou uma nova mensagem');
      const grupo = AvisoMensagem(conversa: 2, titulo: 'Equipe TI', grupo: true, autor: 'Carla Souza', previa: 'segredo', quantas: 3);
      expect(grupo.textoNotificacao, '3 novas mensagens · a última de Carla Souza');
      expect(grupo.textoNotificacao.contains('segredo'), isFalse);
    });

    test('Testar: cada aviso ligado uma vez', () async {
      final t = _novo();
      t.al.definir(notificacao: false);
      await t.al.testar();
      expect(t.al.quadros.value.single.conversa, -1);
      expect(t.notif, isEmpty);
      expect(t.som, hasLength(1));
    });
  });

  group('Mensagem.previa', () {
    Mensagem m(Map<String, dynamic> x) => Mensagem.de({'id': 1, 'user_name': 'Bruno', ...x});
    test('texto, anexo e enquete', () {
      expect(m({'body': 'Oi,\n  tudo bem?'}).previa, 'Oi, tudo bem?');
      expect(m({'attachments': [{'id': 1, 'name': 'nota.pdf'}]}).previa, '📎 nota.pdf');
      expect(m({'body': 'x' * 300}).previa.length, 140);
    });
  });

  group('desenho', () {
    setUpAll(() async {
      await fontes();
      await initializeDateFormatting('pt_BR');
    });

    for (final b in [Brightness.light, Brightness.dark]) {
      final sufixo = b == Brightness.dark ? '_escuro' : '';

      testWidgets('quadros de mensagem nova$sufixo', (t) async {
        t.view.physicalSize = const Size(460, 340);
        t.view.devicePixelRatio = 1;
        final c = await controleFalso(Directory.systemTemp.createTempSync('cc_quadro'));
        final abertas = <int>[];
        c.alertas
          ..chegou(const AvisoMensagem(conversa: 7, titulo: 'Equipe TI', grupo: true, autor: 'Carla Souza', previa: 'Subi a planilha nova na pasta do cliente, podem conferir?', ultimoId: 2))
          ..chegou(const AvisoMensagem(conversa: 5, titulo: 'Bruno Lima', previa: 'Oi, Ana! Consegue me ligar quando puder?', ultimoId: 1))
          ..chegou(const AvisoMensagem(conversa: 5, titulo: 'Bruno Lima', previa: 'É sobre o acordo da Unimed.', ultimoId: 3));
        await t.pumpWidget(app(
            c,
            b,
            Scaffold(
                body: Align(
                    alignment: Alignment.topRight,
                    child: Padding(padding: const EdgeInsets.all(16), child: QuadrosMensagem(c.alertas, aoAbrir: abertas.add))))));
        await t.pump(const Duration(milliseconds: 400));
        expect(find.text('2 novas'), findsOneWidget);
        expect(find.text('Carla Souza: Subi a planilha nova na pasta do cliente, podem conferir?'), findsOneWidget);
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/quadros_mensagem$sufixo.png'));

        await t.tap(find.text('Bruno Lima'));
        await t.pump();
        expect(abertas, [5]);
        expect(c.alertas.quadros.value.map((a) => a.conversa), [7]);
        await t.tap(find.byTooltip('Fechar o aviso'));
        await t.pump();
        expect(c.alertas.quadros.value, isEmpty);
        await t.pumpWidget(const SizedBox());
        t.view.reset();
      });

      testWidgets('configuração dos avisos$sufixo', (t) async {
        t.view.physicalSize = const Size(640, 620);
        t.view.devicePixelRatio = 1;
        final c = await controleFalso(Directory.systemTemp.createTempSync('cc_cfg'));
        await t.pumpWidget(app(c, b, Scaffold(body: Builder(builder: (ctx) {
          return Center(child: TextButton(onPressed: () => showDialog<void>(context: ctx, builder: (_) => DialogoAvisos(c.alertas)), child: const Text('abrir')));
        }))));
        await t.tap(find.text('abrir'));
        await t.pumpAndSettle();
        await t.tap(find.text('Tocar um som'));
        await t.pumpAndSettle();
        expect(c.alertas.som, isFalse);
        expect(c.arm.pref<bool>('som_mensagem', true), isFalse);
        await t.tap(find.text('Tocar um som'));
        await t.pumpAndSettle();
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/avisos_config$sufixo.png'));
        await t.pumpWidget(const SizedBox());
        t.view.reset();
      });
    }

    testWidgets('o quadro some sozinho em 8 s, e o mouse em cima segura', (t) async {
      final c = await controleFalso(Directory.systemTemp.createTempSync('cc_tempo'));
      c.alertas.chegou(const AvisoMensagem(conversa: 5, titulo: 'Bruno Lima', previa: 'Oi', ultimoId: 1));
      await t.pumpWidget(app(c, Brightness.light, Scaffold(body: Align(alignment: Alignment.topRight, child: QuadrosMensagem(c.alertas, aoAbrir: (_) {})))));
      await t.pump(const Duration(seconds: 7));
      expect(c.alertas.quadros.value, hasLength(1));
      await t.pump(const Duration(seconds: 2));
      expect(c.alertas.quadros.value, isEmpty);
    });
  });
}
