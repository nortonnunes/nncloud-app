// Renderiza as telas com fontes de verdade (Roboto e os ícones do Material) e a
// API FALSA (MockClient), para conferir o desenho:
//   flutter test test/telas_test.dart --update-goldens   → gera os PNG em test/goldens/
// Sem `--update-goldens` confere contra eles.
import 'dart:convert';
import 'dart:io';

import 'package:conecta_callcenter/api/cliente.dart';
import 'package:conecta_callcenter/servicos/armazenamento.dart';
import 'package:conecta_callcenter/servicos/atualizacao.dart';
import 'package:conecta_callcenter/servicos/controle.dart';
import 'package:conecta_callcenter/servicos/notificacoes.dart';
import 'package:conecta_callcenter/telas/casca.dart';
import 'package:conecta_callcenter/tema.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path/path.dart' as p;

Future<void> fontes() async {
  final raiz = p.dirname(p.dirname(File(Platform.resolvedExecutable).resolveSymbolicLinksSync()));
  final mat = Directory(p.join(p.dirname(p.dirname(raiz)), 'artifacts', 'material_fonts'));
  Future<void> carregar(String familia, List<String> arquivos) async {
    final l = FontLoader(familia);
    for (final a in arquivos) {
      final f = File(p.join(mat.path, a));
      if (f.existsSync()) l.addFont(Future.value(ByteData.view(f.readAsBytesSync().buffer)));
    }
    await l.load();
  }

  await carregar('Roboto', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']);
  await carregar('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

String _d(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

Map<String, dynamic> _msg(int id, int uid, String nome, String quando, {String corpo = '', String? html, bool mine = false, Map? reply, List? reacoes,
        List? anexos, bool editada = false, bool encaminhada = false, Map? poll, bool mencionaMim = false}) =>
    {
      'id': id, 'user_id': uid, 'user_name': nome, 'avatar': null, 'mine': mine, 'body': corpo, 'format': 'text', 'body_html': html,
      'at': quando, 'created_at': null, 'edited': editada, 'forwarded': encaminhada, 'ts': 0, 'can_edit': false,
      'attachments': anexos ?? [], 'reply': reply, 'reactions': reacoes ?? [], 'mentions': [], 'mentions_me': mencionaMim, 'poll': poll,
    };

http.Client apiFalsa() {
  final png = File('assets/icone.png').readAsBytesSync();
  final hoje = DateTime.now();
  final ontem = hoje.subtract(const Duration(days: 1));
  final conversas = [
    {'id': 5, 'title': 'Bruno Lima', 'type': 'direct', 'preview': 'Combinado, te mando o arquivo', 'unread': 0, 'is_favorite': true, 'is_archived': false,
      'avatar': null, 'updated_at': '${hoje.year}-${hoje.month.toString().padLeft(2, '0')}-${hoje.day.toString().padLeft(2, '0')} 10:42:00',
      'status': {'codigo': 'almoco', 'rotulo': 'Em almoço', 'mensagem': 'volto às 14h', 'ate': '14:30', 'online': true, 'texto': 'Em almoço — volto às 14h · até 14:30'}},
    {'id': 6, 'title': 'Supervisão Turno A', 'type': 'group', 'preview': 'Carla: reunião às 15h na sala 2', 'unread': 3, 'is_favorite': true, 'is_archived': false,
      'avatar': null, 'updated_at': '${hoje.year}-${hoje.month.toString().padLeft(2, '0')}-${hoje.day.toString().padLeft(2, '0')} 10:15:00', 'status': null},
    {'id': 7, 'title': 'Carla Souza', 'type': 'direct', 'preview': 'Ok, obrigada!', 'unread': 0, 'is_favorite': false, 'is_archived': false, 'avatar': null,
      'updated_at': '2026-11-20 16:00:00', 'status': {'codigo': 'disponivel', 'rotulo': 'Disponível', 'mensagem': '', 'ate': null, 'online': true, 'texto': 'Disponível'}},
    {'id': 8, 'title': 'Diego Alves', 'type': 'direct', 'preview': '📎 Anexo', 'unread': 1, 'is_favorite': false, 'is_archived': false, 'avatar': null,
      'updated_at': '2026-11-18 09:00:00', 'status': {'codigo': 'offline', 'rotulo': 'Offline', 'mensagem': '', 'ate': null, 'online': false, 'texto': 'Offline · visto há 2 h'}},
  ];
  final msgs = [
    _msg(101, 2, 'Bruno Lima', '${_d(ontem)} 17:40', corpo: 'Oi Ana, conseguiu falar com o devedor do contrato 4471?'),
    _msg(102, 1, 'Ana Lima', '${_d(ontem)} 17:52', mine: true, corpo: 'Consegui sim! Ele aceitou a proposta à vista.',
        html: 'Consegui sim! Ele aceitou a proposta <b>à vista</b>.', reacoes: [{'emoji': '👍', 'count': 1, 'mine': false, 'users': ['Bruno Lima']}]),
    _msg(103, 2, 'Bruno Lima', '${_d(hoje)} 09:05', corpo: 'Ótimo. Lembra de registrar na ficha e mandar o comprovante: https://nnconecta.com/operadoras'),
    _msg(104, 1, 'Ana Lima', '${_d(hoje)} 09:12', mine: true, corpo: 'Registrado. Segue o print da tela:', anexos: [
      {'id': 9, 'name': 'print-ficha.png', 'size': 84211, 'mime': 'image/png', 'is_image': true, 'is_audio': false,
        'url': '/v1/callapp/chat/attachment?a=9', 'thumb_url': '/v1/callapp/chat/attachment?a=9&mini=1'},
    ], reply: {'id': 103, 'author': 'Bruno Lima', 'text': 'Ótimo. Lembra de registrar na ficha e mandar o comprovante'}),
    _msg(105, 2, 'Bruno Lima', '${_d(hoje)} 10:30', corpo: 'Perfeito! Atenção: a carteira da Unimed vira amanhã.',
        html: 'Perfeito! <span class="im-cor-1"><b>Atenção:</b></span> a carteira da Unimed vira <u>amanhã</u>.', editada: true),
    _msg(106, 2, 'Bruno Lima', '${_d(hoje)} 10:41', corpo: '', anexos: [
      {'id': 10, 'name': 'roteiro-ligacao.pdf', 'size': 248000, 'mime': 'application/pdf', 'is_image': false, 'is_audio': false,
        'url': '/v1/callapp/chat/attachment?a=10', 'thumb_url': null},
      {'id': 11, 'name': 'orientacao.mp3', 'size': 912000, 'mime': 'audio/mpeg', 'is_image': false, 'is_audio': true,
        'url': '/v1/callapp/chat/attachment?a=11', 'thumb_url': null},
    ], encaminhada: true),
    _msg(107, 1, 'Ana Lima', '${_d(hoje)} 10:42', mine: true, corpo: 'Combinado, te mando o arquivo'),
  ];
  return MockClient((req) async {
    final caminho = req.url.path;
    http.Response json(Object d) => http.Response(jsonEncode({'data': d}), 200, headers: {'content-type': 'application/json; charset=utf-8'});
    if (caminho.endsWith('/chat/attachment') || caminho.endsWith('/news/midia')) return http.Response.bytes(png, 200);
    if (caminho.endsWith('/chat/socket')) return json({'enabled': false});
    if (caminho.endsWith('/chat/conversations')) return json(conversas);
    if (caminho.endsWith('/chat/conversations/5')) {
      return json({
        'id': 5, 'title': 'Bruno Lima', 'type': 'direct', 'messages': msgs,
        'read_state': {'participants': [
          {'user_id': 1, 'user_name': 'Ana Lima', 'last_read_message_id': 107, 'last_delivered_message_id': 107},
          {'user_id': 2, 'user_name': 'Bruno Lima', 'last_read_message_id': 104, 'last_delivered_message_id': 107},
        ], 'recipient_count': 1},
        'typing': ['Bruno Lima'],
        'participants': [{'id': 1, 'name': 'Ana Lima'}, {'id': 2, 'name': 'Bruno Lima'}],
        'meta': {'type': 'direct', 'is_creator': false, 'is_admin': false, 'member_ids': [1, 2], 'admin_ids': [], 'can_delete': false, 'avatar': null},
      });
    }
    if (caminho.endsWith('/inicio')) {
      Map cartao(int id, String t, String r, int cat) => {
            'id': id, 'slug': 's$id', 'titulo': t, 'resumo': r, 'categoria': {'id': cat, 'nome': ['Institucional', 'Operação', 'Pessoas'][cat], 'slug': 'c', 'cor': cat},
            'publicado_em': '2026-11-25 09:00:00', 'data': '25/11/2026', 'capa_chave': 'a' * 32, 'capa_w': 1200, 'capa_h': 675, 'youtube_id': null,
            'tipo': 'texto', 'leituras': 120 + id, 'curtidas': 14, 'comentarios': 3, 'autor': 'Comunicação', 'destaque': id == 1,
          };
      return json({
        'news': {
          'nome': 'NN News',
          'destaques': [cartao(1, 'Nova operação começa em dezembro', 'A equipe do Turno A assume a carteira nova a partir do dia 2.', 1)],
          'ultimas': [
            cartao(2, 'Campanha de fim de ano', 'Metas e premiação do último trimestre.', 0),
            cartao(3, 'Boas-vindas aos novos atendentes', 'Doze pessoas entram no time nesta semana.', 2),
            cartao(4, 'Atualização do discador', 'O que muda na Mesa a partir de segunda.', 1),
          ],
        },
        'avisos': [
          {'id': 1, 'titulo': 'Manutenção do sistema no sábado', 'resumo': 'Das 8h às 10h o NN Conecta fica fora do ar.',
            'corpo': '<p>Das <b>8h às 10h</b> o NN Conecta fica fora do ar para atualização. Planeje os retornos agendados.</p>', 'data': '2026-11-25 08:00:00', 'destaque': true},
          {'id': 2, 'titulo': 'Uniforme às sextas', 'resumo': 'Liberado o uso de roupa casual.', 'corpo': '', 'data': '2026-11-20 08:00:00', 'destaque': false},
        ],
        'aniversariantes': [
          {'id': 1, 'nome': 'Ana Lima', 'cargo': 'Tele atendente', 'avatar': null, 'dia': hoje.day, 'hoje': true, 'eu': true},
          {'id': 3, 'nome': 'Carla Souza', 'cargo': 'Supervisora', 'avatar': null, 'dia': 28, 'hoje': false, 'eu': false},
        ],
      });
    }
    return json({});
  });
}

Future<Controle> controleFalso(Directory dir) async {
  final arm = Armazenamento()..usarTokenFixo = true;
  await arm.iniciar(base: dir);
  final c = Controle(arm, api: Api(base: 'http://teste', chave: 'nncd_x', token: 'nncall_y', cliente: apiFalsa()))
    ..fase = Fase.pronto
    ..eu = {
      'id': 1, 'nome': 'Ana Lima', 'primeiro': 'Ana', 'email': 'ana@nortonnunes.com.br', 'avatar': null,
      'status': {'codigo': 'disponivel', 'escolhido': 'disponivel', 'mensagem': ''},
      'computador': {'nome': 'CALL-PC-07', 'so': 'windows'},
    };
  return c;
}

Widget app(Controle c, Brightness b, Widget filho) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: temaDe(b == Brightness.dark ? Paleta.escuroPadrao : Paleta.claroPadrao, b, const [Color(0xFF993635), Color(0xFF1552D0), Color(0xFF0B7A44)]),
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: filho,
    );

void main() {
  setUpAll(() async {
    await fontes();
    await initializeDateFormatting('pt_BR');
  });

  for (final b in [Brightness.light, Brightness.dark]) {
    final sufixo = b == Brightness.dark ? '_escuro' : '';

    testWidgets('painel inicial$sufixo', (t) async {
      t.view.physicalSize = const Size(1440, 1000);
      t.view.devicePixelRatio = 1;
      final dir = Directory.systemTemp.createTempSync('cc_ini');
      final c = await controleFalso(dir);
      if (b == Brightness.dark) c.modo = 'escuro';
      Casca.aba.value = 0;
      await t.pumpWidget(app(c, b, Casca(c, Atualizador(c, c.arm, Notificacoes()), aoMinimizar: () async {})));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 600)));
      await t.pump(const Duration(milliseconds: 50));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await t.pump();
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/inicio$sufixo.png'));
      await t.pumpWidget(const SizedBox());
      t.view.reset();
    });

    testWidgets('conversa aberta$sufixo', (t) async {
      t.view.physicalSize = const Size(1440, 1000);
      t.view.devicePixelRatio = 1;
      final dir = Directory.systemTemp.createTempSync('cc_conv');
      final c = await controleFalso(dir);
      if (b == Brightness.dark) c.modo = 'escuro';
      Casca.aba.value = 1;
      await t.pumpWidget(app(c, b, Casca(c, Atualizador(c, c.arm, Notificacoes()), aoMinimizar: () async {})));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await t.pump();
      Casca.abrirConversa(5);
      await t.pump();
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 600)));
      await t.pump(const Duration(milliseconds: 50));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await t.pump();
      expect(find.text('Bruno Lima está digitando…'), findsOneWidget);
      expect(find.textContaining('A resposta pode demorar'), findsOneWidget);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/conversa$sufixo.png'));
      await t.pumpWidget(const SizedBox());
      t.view.reset();
    });
  }
}
