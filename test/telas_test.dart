// Renderiza as telas com fontes de verdade (Roboto e os ícones do Material) e a
// API FALSA (MockClient), para conferir o desenho:
//   flutter test test/telas_test.dart --update-goldens   → gera os PNG em test/goldens/
// Sem `--update-goldens` confere contra eles.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:nn_conversas/api/cliente.dart';
import 'package:nn_conversas/config.dart';
import 'package:nn_conversas/servicos/armazenamento.dart';
import 'package:nn_conversas/servicos/atualizacao.dart';
import 'package:nn_conversas/servicos/controle.dart';
import 'package:nn_conversas/servicos/notificacoes.dart';
import 'package:nn_conversas/telas/acesso.dart';
import 'package:nn_conversas/telas/casca.dart';
import 'package:nn_conversas/tema.dart';
import 'package:nn_conversas/widgets/topo.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path/path.dart' as p;
import 'package:crypto/crypto.dart';

Future<void> fontes() async {
  final raiz = p.dirname(
      p.dirname(File(Platform.resolvedExecutable).resolveSymbolicLinksSync()));
  final mat = Directory(
      p.join(p.dirname(p.dirname(raiz)), 'artifacts', 'material_fonts'));
  Future<void> carregar(String familia, List<String> arquivos) async {
    final l = FontLoader(familia);
    for (final a in arquivos) {
      final f = File(p.join(mat.path, a));
      if (f.existsSync()) {
        l.addFont(Future.value(ByteData.view(f.readAsBytesSync().buffer)));
      }
    }
    await l.load();
  }

  await carregar(
      'Roboto', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']);
  await carregar('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

String _d(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

Map<String, dynamic> _msg(int id, int uid, String nome, String quando,
        {String corpo = '',
        String? html,
        bool mine = false,
        Map? reply,
        List? reacoes,
        List? anexos,
        bool editada = false,
        bool encaminhada = false,
        Map? poll,
        bool mencionaMim = false}) =>
    {
      'id': id,
      'user_id': uid,
      'user_name': nome,
      'avatar': null,
      'mine': mine,
      'body': corpo,
      'format': 'text',
      'body_html': html,
      'at': quando,
      'created_at': null,
      'edited': editada,
      'forwarded': encaminhada,
      'ts': 0,
      'can_edit': false,
      'attachments': anexos ?? [],
      'reply': reply,
      'reactions': reacoes ?? [],
      'mentions': [],
      'mentions_me': mencionaMim,
      'poll': poll,
    };

/// O "instalador" que a API falsa entrega (a atualização confere tamanho e SHA-256).
final instaladorFalso =
    utf8.encode('instalador de teste do NN Conversas');
Map<String, dynamic> infoVersao(String v) => {
      'versao': v,
      'nome': 'NN-Conversas-$v.exe',
      'tamanho': instaladorFalso.length,
      'sha256': sha256.convert(instaladorFalso).toString()
    };
var downloadsFeitos = 0;
var falharDownload = false;

http.Client apiFalsa() {
  final png = File('assets/icone.png').readAsBytesSync();
  final hoje = DateTime.now();
  final ontem = hoje.subtract(const Duration(days: 1));
  final conversas = [
    {
      'id': 5,
      'title': 'Bruno Lima',
      'type': 'direct',
      'preview': 'Combinado, te mando o arquivo',
      'unread': 0,
      'is_favorite': true,
      'is_archived': false,
      'avatar': null,
      'updated_at':
          '${hoje.year}-${hoje.month.toString().padLeft(2, '0')}-${hoje.day.toString().padLeft(2, '0')} 10:42:00',
      'status': {
        'codigo': 'almoco',
        'rotulo': 'Em almoço',
        'mensagem': 'volto às 14h',
        'ate': '14:30',
        'online': true,
        'texto': 'Em almoço — volto às 14h · até 14:30'
      }
    },
    {
      'id': 6,
      'title': 'Supervisão Turno A',
      'type': 'group',
      'preview': 'Carla: reunião às 15h na sala 2',
      'unread': 3,
      'is_favorite': true,
      'is_archived': false,
      'avatar': null,
      'updated_at':
          '${hoje.year}-${hoje.month.toString().padLeft(2, '0')}-${hoje.day.toString().padLeft(2, '0')} 10:15:00',
      'status': null
    },
    {
      'id': 7,
      'title': 'Carla Souza',
      'type': 'direct',
      'preview': 'Ok, obrigada!',
      'unread': 0,
      'is_favorite': false,
      'is_archived': false,
      'avatar': null,
      'updated_at': '2026-11-20 16:00:00',
      'status': {
        'codigo': 'disponivel',
        'rotulo': 'Disponível',
        'mensagem': '',
        'ate': null,
        'online': true,
        'texto': 'Disponível'
      }
    },
    {
      'id': 8,
      'title': 'Diego Alves',
      'type': 'direct',
      'preview': '📎 Anexo',
      'unread': 1,
      'is_favorite': false,
      'is_archived': false,
      'avatar': null,
      'updated_at': '2026-11-18 09:00:00',
      'status': {
        'codigo': 'offline',
        'rotulo': 'Offline',
        'mensagem': '',
        'ate': null,
        'online': false,
        'texto': 'Offline · visto há 2 h'
      }
    },
  ];
  final msgs = [
    _msg(101, 2, 'Bruno Lima', '${_d(ontem)} 17:40',
        corpo: 'Oi Ana, conseguiu falar com o devedor do contrato 4471?'),
    _msg(102, 1, 'Ana Lima', '${_d(ontem)} 17:52',
        mine: true,
        corpo: 'Consegui sim! Ele aceitou a proposta à vista.',
        html: 'Consegui sim! Ele aceitou a proposta <b>à vista</b>.',
        reacoes: [
          {
            'emoji': '👍',
            'count': 1,
            'mine': false,
            'users': ['Bruno Lima']
          }
        ]),
    _msg(103, 2, 'Bruno Lima', '${_d(hoje)} 09:05',
        corpo:
            'Ótimo. Lembra de registrar na ficha e mandar o comprovante: https://nnconecta.com/operadoras'),
    _msg(104, 1, 'Ana Lima', '${_d(hoje)} 09:12',
        mine: true,
        corpo: 'Registrado. Segue o print da tela:',
        anexos: [
          {
            'id': 9,
            'name': 'print-ficha.png',
            'size': 84211,
            'mime': 'image/png',
            'is_image': true,
            'is_audio': false,
            'url': '/v1/callapp/chat/attachment?a=9',
            'thumb_url': '/v1/callapp/chat/attachment?a=9&mini=1'
          },
        ],
        reply: {
          'id': 103,
          'author': 'Bruno Lima',
          'text': 'Ótimo. Lembra de registrar na ficha e mandar o comprovante'
        }),
    _msg(105, 2, 'Bruno Lima', '${_d(hoje)} 10:30',
        corpo: 'Perfeito! Atenção: a carteira da Unimed vira amanhã.',
        html:
            'Perfeito! <span class="im-cor-1"><b>Atenção:</b></span> a carteira da Unimed vira <u>amanhã</u>.',
        editada: true),
    _msg(106, 2, 'Bruno Lima', '${_d(hoje)} 10:41',
        corpo: '',
        anexos: [
          {
            'id': 10,
            'name': 'roteiro-ligacao.pdf',
            'size': 248000,
            'mime': 'application/pdf',
            'is_image': false,
            'is_audio': false,
            'url': '/v1/callapp/chat/attachment?a=10',
            'thumb_url': null
          },
          {
            'id': 11,
            'name': 'orientacao.mp3',
            'size': 912000,
            'mime': 'audio/mpeg',
            'is_image': false,
            'is_audio': true,
            'url': '/v1/callapp/chat/attachment?a=11',
            'thumb_url': null
          },
        ],
        encaminhada: true),
    _msg(107, 1, 'Ana Lima', '${_d(hoje)} 10:42',
        mine: true, corpo: 'Combinado, te mando o arquivo'),
  ];
  return MockClient((req) async {
    final caminho = req.url.path;
    http.Response json(Object d) => http.Response(jsonEncode({'data': d}), 200,
        headers: {'content-type': 'application/json; charset=utf-8'});
    if (caminho.endsWith('/chat/attachment') ||
        caminho.endsWith('/news/midia')) {
      return http.Response.bytes(png, 200);
    }
    if (caminho.endsWith('/chat/socket')) return json({'enabled': false});
    if (caminho.endsWith('/app/baixar')) {
      downloadsFeitos++;
      return falharDownload
          ? http.Response('{"error":{"status":500,"message":"Falhou."}}', 500)
          : http.Response.bytes(instaladorFalso, 200);
    }
    if (caminho.endsWith('/chat/conversations')) return json(conversas);
    if (caminho.endsWith('/chat/conversations/5')) {
      return json({
        'id': 5,
        'title': 'Bruno Lima',
        'type': 'direct',
        'messages': msgs,
        'read_state': {
          'participants': [
            {
              'user_id': 1,
              'user_name': 'Ana Lima',
              'last_read_message_id': 107,
              'last_delivered_message_id': 107
            },
            {
              'user_id': 2,
              'user_name': 'Bruno Lima',
              'last_read_message_id': 104,
              'last_delivered_message_id': 107
            },
          ],
          'recipient_count': 1
        },
        'typing': ['Bruno Lima'],
        'participants': [
          {'id': 1, 'name': 'Ana Lima'},
          {'id': 2, 'name': 'Bruno Lima'}
        ],
        'meta': {
          'type': 'direct',
          'is_creator': false,
          'is_admin': false,
          'member_ids': [1, 2],
          'admin_ids': [],
          'can_delete': false,
          'avatar': null
        },
      });
    }
    if (caminho.endsWith('/inicio')) {
      Map cartao(int id, String t, String r, int cat) => {
            'id': id,
            'slug': 's$id',
            'titulo': t,
            'resumo': r,
            'categoria': {
              'id': cat,
              'nome': ['Institucional', 'Operação', 'Pessoas'][cat],
              'slug': 'c',
              'cor': cat
            },
            'publicado_em': '2026-11-25 09:00:00',
            'data': '25/11/2026',
            'capa_chave': 'a' * 32,
            'capa_w': 1200,
            'capa_h': 675,
            'youtube_id': null,
            'tipo': 'texto',
            'leituras': 120 + id,
            'curtidas': 14,
            'comentarios': 3,
            'autor': 'Comunicação',
            'destaque': id == 1,
          };
      return json({
        'news': {
          'nome': 'NN News',
          'destaques': [
            cartao(
                1,
                'Nova operação começa em dezembro',
                'A equipe do Turno A assume a carteira nova a partir do dia 2.',
                1)
          ],
          'ultimas': [
            cartao(2, 'Campanha de fim de ano',
                'Metas e premiação do último trimestre.', 0),
            cartao(3, 'Boas-vindas a quem chegou',
                'Doze pessoas entram na empresa nesta semana.', 2),
            cartao(4, 'Atualização do discador',
                'O que muda na Mesa a partir de segunda.', 1),
          ],
        },
        'avisos': [
          {
            'id': 1,
            'titulo': 'Manutenção do sistema no sábado',
            'resumo': 'Das 8h às 10h o NN Conecta fica fora do ar.',
            'corpo':
                '<p>Das <b>8h às 10h</b> o NN Conecta fica fora do ar para atualização. Planeje os retornos agendados.</p>',
            'data': '2026-11-25 08:00:00',
            'destaque': true
          },
          {
            'id': 2,
            'titulo': 'Uniforme às sextas',
            'resumo': 'Liberado o uso de roupa casual.',
            'corpo': '',
            'data': '2026-11-20 08:00:00',
            'destaque': false
          },
        ],
        'aniversariantes': [
          {
            'id': 1,
            'nome': 'Ana Lima',
            'cargo': 'Analista',
            'avatar': null,
            'dia': hoje.day,
            'hoje': true,
            'eu': true
          },
          {
            'id': 3,
            'nome': 'Carla Souza',
            'cargo': 'Supervisora',
            'avatar': null,
            'dia': 28,
            'hoje': false,
            'eu': false
          },
        ],
      });
    }
    return json({});
  });
}

Future<Controle> controleFalso(Directory dir) async {
  final arm = Armazenamento()..usarTokenFixo = true;
  await arm.iniciar(base: dir);
  final c = Controle(arm,
      api: Api(
          base: 'http://teste',
          token: 'nnconv_y',
          cliente: apiFalsa()))
    ..fase = Fase.pronto
    ..eu = {
      'id': 1,
      'nome': 'Ana Lima',
      'primeiro': 'Ana',
      'email': 'ana@nortonnunes.com.br',
      'avatar': null,
      'status': {
        'codigo': 'disponivel',
        'escolhido': 'disponivel',
        'mensagem': ''
      },
      'dispositivo': {'nome': 'NOTE-ANA', 'so': 'windows'},
      'pode': {'criar_grupo': true, 'news': true},
    }
    ..aparencia = {
      'sistema': 'Conecta',
      'empresa': 'Norton Nunes Recuperação de Crédito',
      'site_url': 'https://nnconecta.com',
      'rodape': {
        'texto':
            'Conecta · Norton Nunes Recuperação de Crédito. Todos os direitos reservados.',
        'denuncia': 'https://nnconecta.com/denuncia',
        'lgpd': 'https://nnconecta.com/lgpd',
      },
    };
  return c;
}

/// O tema como o `main.dart` monta: as cores da aparência (padrão quando não há).
Widget app(Controle c, Brightness b, Widget filho) {
  final a = c.aparencia;
  final escuro = b == Brightness.dark;
  final paleta = Paleta.de(
      ((a?['cores'] as Map?) ?? const {})[escuro ? 'escuro' : 'claro'] as Map?,
      ((a?['topo'] as Map?) ?? const {})[escuro ? 'escuro' : 'claro'] as Map?,
      escuro ? Paleta.escuroPadrao : Paleta.claroPadrao);
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: temaDe(paleta, b,
        const [Color(0xFF993635), Color(0xFF1552D0), Color(0xFF0B7A44)]),
    locale: const Locale('pt', 'BR'),
    supportedLocales: const [Locale('pt', 'BR')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: filho,
  );
}

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
      await t.pumpWidget(app(
          c,
          b,
          Casca(c, Atualizador(c, c.arm, Notificacoes()),
              aoMinimizar: () async {})));
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 600)));
      await t.pump(const Duration(milliseconds: 50));
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 300)));
      await t.pump();
      await expectLater(find.byType(MaterialApp),
          matchesGoldenFile('goldens/inicio$sufixo.png'));
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
      await t.pumpWidget(app(
          c,
          b,
          Casca(c, Atualizador(c, c.arm, Notificacoes()),
              aoMinimizar: () async {})));
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 300)));
      await t.pump();
      Casca.abrirConversa(5);
      await t.pump();
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 600)));
      await t.pump(const Duration(milliseconds: 50));
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 300)));
      await t.pump();
      expect(find.text('Bruno Lima está digitando…'), findsOneWidget);
      expect(find.textContaining('A resposta pode demorar'), findsOneWidget);
      await expectLater(find.byType(MaterialApp),
          matchesGoldenFile('goldens/conversa$sufixo.png'));
      await t.pumpWidget(const SizedBox());
      t.view.reset();
    });

    /// O tema sazonal Black Friday de produção: imagem do topo, logo "gg" e a barra escura.
    void blackFriday(Controle c) {
      c.aparencia = {
        ...c.aparencia!,
        'logo_tam': 'gg',
        'topo': {
          'claro': {'ini': '#0a0a0a', 'fim': '#3a3a3a'},
          'escuro': {'ini': '#000000', 'fim': '#2a2a2a'},
        },
        'sazonal': {
          'chave': 'black-friday',
          'rotulo': 'Black Friday',
          'fundo': 'http://teste/uploads/fundo.png'
        },
      };
    }

    testWidgets('topo com tema sazonal e versão nova$sufixo', (t) async {
      // A imagem do topo decodificada ANTES (fora do relógio falso): a faixa a
      // encontra pronta no cache.
      final banner = MemoryImage(
          File('test/fixtures/fundo_black_friday.png').readAsBytesSync());
      FaixaTopo.imagem = (_) => banner;
      addTearDown(() => FaixaTopo.imagem = NetworkImage.new);
      await t.runAsync(() async {
        final pronto = Completer<void>();
        banner
            .resolve(ImageConfiguration.empty)
            .addListener(ImageStreamListener((_, __) {
              if (!pronto.isCompleted) pronto.complete();
            }, onError: (_, __) {
              if (!pronto.isCompleted) pronto.complete();
            }));
        await pronto.future.timeout(const Duration(seconds: 5));
      });
      t.view.physicalSize = const Size(1440, 900);
      t.view.devicePixelRatio = 1;
      final dir = Directory.systemTemp.createTempSync('cc_bf');
      final c = await controleFalso(dir);
      blackFriday(c);
      if (b == Brightness.dark) c.modo = 'escuro';
      Casca.aba.value = 0;
      falharDownload = false;
      final at = Atualizador(c, c.arm, Notificacoes());
      await t.pumpWidget(app(c, b, Casca(c, at, aoMinimizar: () async {})));
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 600)));
      await t.pump();
      // A faixa branca da borda esquerda da imagem (10 colunas) foi medida e cortada.
      expect(
          find.byWidgetPredicate(
              (w) => w is CustomPaint && w.painter is PintorFundoTopo),
          findsOneWidget);
      // Os avisos saíram do painel; o link continua no menu.
      expect(find.text('Quadro de avisos'), findsNothing);
      expect(find.text('Avisos'), findsOneWidget);
      // O minimizar é ícone no topo (não é mais link do menu).
      expect(find.text('Minimizar'), findsNothing);
      expect(
          find.byTooltip(
              'Minimizar — o app continua no ícone ao lado do relógio'),
          findsOneWidget);

      // O /eu traz a versão publicada: o app baixa, confere e mostra o aviso.
      c.eu = {...c.eu!, 'app': infoVersao('9.9.9')};
      // O download (arquivo + SHA-256) roda fora do relógio falso do teste.
      await t.runAsync(() async {
        c.notifyListeners();
        for (var i = 0; i < 40 && at.pronto == null && at.erro == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      });
      await t.pump();
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)));
      await t.pump();
      expect(at.versaoNova, '9.9.9');
      expect(at.pronto, isNotNull, reason: at.erro);
      expect(find.text('Nova versão do NN Conversas'), findsOneWidget);
      expect(find.textContaining('Pronta para instalar'), findsOneWidget);
      await t.pump(const Duration(milliseconds: 400));
      await expectLater(find.byType(MaterialApp),
          matchesGoldenFile('goldens/atualizacao_aviso$sufixo.png'));

      // "Depois": o aviso fecha e o botão fica no topo.
      await t.tap(find.text('Depois'));
      await t.pump(const Duration(milliseconds: 400));
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('Atualizar para a 9.9.9'), findsOneWidget);
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 300)));
      await t.pump();
      await expectLater(find.byType(MaterialApp),
          matchesGoldenFile('goldens/topo_sazonal$sufixo.png'));
      // O aviso não volta sozinho para a mesma versão.
      c.notifyListeners();
      await t.pump();
      expect(find.text('Nova versão do NN Conversas'), findsNothing);
      await t.pumpWidget(const SizedBox());
      t.view.reset();
    });

  }

  /// O login numa etapa, como o servidor a descreve.
  Future<Controle> controleLogin(EtapaLogin etapa, {Map<String, dynamic> passo = const {}}) async {
    final c = await controleFalso(Directory.systemTemp.createTempSync('cv_login'));
    c
      ..fase = Fase.login
      ..eu = null
      ..etapa = etapa
      ..ticket = 'nnconvl_x'
      ..emailDigitado = 'ana@nortonnunes.com.br'
      ..passo = passo;
    return c;
  }

  Future<void> desenharLogin(WidgetTester t, Controle c, Brightness b, String golden) async {
    t.view.physicalSize = const Size(1280, 900);
    t.view.devicePixelRatio = 1;
    await t.pumpWidget(app(c, b, ListenableBuilder(listenable: c, builder: (_, __) => TelaLogin(c))));
    await t.pump(const Duration(milliseconds: 100));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$golden.png'));
  }

  const email2fa = {'destino': 'an•••@nortonnunes.com.br', 'pendente': null};

  for (final b in [Brightness.light, Brightness.dark]) {
    final sufixo = b == Brightness.dark ? '_escuro' : '';
    testWidgets('login: e-mail e senha$sufixo', (t) async {
      final c = await controleLogin(EtapaLogin.senha);
      c.avisoLogin = b == Brightness.dark ? 'Sua sessão expirou. Entre de novo.' : null;
      await desenharLogin(t, c, b, 'login_senha$sufixo');
      expect(find.text('Entrar com QR code'), findsOneWidget);
      expect(find.text('Esqueci minha senha'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      t.view.reset();
    });

    testWidgets('login: verificação em duas etapas$sufixo', (t) async {
      final c = await controleLogin(EtapaLogin.doisFatores, passo: {
        'email': email2fa,
        'celular': {'suspenso': 0},
      })
        ..restamTentativas = 3;
      await desenharLogin(t, c, b, 'login_2fa$sufixo');
      expect(find.text('Restam 3 tentativas.'), findsOneWidget);
      expect(find.text('Enviar código por e-mail para an•••@nortonnunes.com.br'), findsOneWidget);
      expect(find.text('Aprovar no celular (app NN Conecta)'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      t.view.reset();
    });
  }

  testWidgets('login: esperando o celular', (t) async {
    final c = await controleLogin(EtapaLogin.doisFatores, passo: {'email': email2fa, 'celular': {'suspenso': 0}})
      ..celularStatus = 'pendente'
      ..celularRestam = 97;
    await desenharLogin(t, c, Brightness.light, 'login_celular');
    expect(find.text('Toque em "Aprovar" no app NN Conecta do seu celular.'), findsOneWidget);
    expect(find.text('O pedido vale por mais 97 s.'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    t.view.reset();
  });

  testWidgets('login: política de uso', (t) async {
    final c = await controleLogin(EtapaLogin.politica, passo: {
      'titulo': 'Contrato de Adesão e Política de Uso dos Sistemas',
      'versao': '1.0',
      'conteudo': '1. OBJETO E ACEITE\n\n1.1. Este instrumento estabelece as regras de uso dos sistemas, aplicativos, contas de e-mail e demais recursos de tecnologia disponibilizados ao colaborador.\n\n1.2. Ao aceitar, o usuário declara ter lido e compreendido todas as cláusulas.\n\n2. ACESSO\n\n2.1. O acesso é pessoal e intransferível.',
      'nome': 'Ana Lima',
      'email': 'ana@nortonnunes.com.br',
      'cpf': '',
      'aviso': 'O aceite é registrado eletronicamente com data, hora, seu identificador de usuário e endereço IP, servindo como assinatura para fins de comprovação.',
    });
    await desenharLogin(t, c, Brightness.light, 'login_politica');
    // Sem marcar o aceite, nem chama o servidor.
    await t.tap(find.text('Aceitar e continuar'));
    await t.pump();
    expect(find.text('Marque "Li e aceito" para continuar.'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    t.view.reset();
  });

  testWidgets('login: configurar o app autenticador', (t) async {
    final c = await controleLogin(EtapaLogin.setup, passo: {
      'segredo': 'JBSWY3DPEHPK3PXP',
      'uri': 'otpauth://totp/Conecta:ana%40nortonnunes.com.br?secret=JBSWY3DPEHPK3PXP&issuer=Conecta',
      'emissor': 'Conecta',
      'conta': 'ana@nortonnunes.com.br',
      'email': email2fa,
    });
    await desenharLogin(t, c, Brightness.light, 'login_setup');
    expect(find.text('JBSW Y3DP EHPK 3PXP'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    t.view.reset();
  });

  testWidgets('login: QR code', (t) async {
    final c = await controleLogin(EtapaLogin.qr)
      ..qr = {'token': 'abc', 'segredo': 's', 'payload': 'nnlogin:${'a' * 64}', 'ttl': 120}
      ..qrStatus = 'pending'
      ..qrCriado = DateTime.now();
    await desenharLogin(t, c, Brightness.light, 'login_qr');
    expect(find.textContaining('Válido por mais'), findsOneWidget);
    // "Entrar com e-mail e senha" volta ao começo.
    await t.tap(find.text('Entrar com e-mail e senha'));
    await t.pump();
    expect(c.etapa, EtapaLogin.senha);
    expect(find.text('Entrar com QR code'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    t.view.reset();
  });

  testWidgets('sem a permissão do NN News, o menu não tem a aba', (t) async {
    t.view.physicalSize = const Size(1280, 800);
    t.view.devicePixelRatio = 1;
    final c = await controleFalso(Directory.systemTemp.createTempSync('cv_semnews'));
    c.eu = {...c.eu!, 'pode': {'criar_grupo': false, 'news': false}};
    Casca.aba.value = 2;
    await t.pumpWidget(app(c, Brightness.light, Casca(c, Atualizador(c, c.arm, Notificacoes()), aoMinimizar: () async {})));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await t.pump();
    expect(find.text('NN News'), findsNothing);
    expect(find.text('Conversas'), findsWidgets);
    await t.pumpWidget(const SizedBox());
    t.view.reset();
  });

  test('versão nova: o /eu avisa, falha não vira download a cada 30 s',
      () async {
    final dir = Directory.systemTemp.createTempSync('cc_at_falha');
    final c = await controleFalso(dir);
    final at = Atualizador(c, c.arm, Notificacoes());
    downloadsFeitos = 0;
    falharDownload = true;
    // Mesma versão instalada: nada acontece.
    c.eu = {...c.eu!, 'app': infoVersao(AppConfig.versao)};
    c.notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(at.versaoNova, isNull);
    expect(downloadsFeitos, 0);
    // Versão maior: tenta baixar uma vez, falha, e o /eu seguinte NÃO baixa de novo.
    c.eu = {...c.eu!, 'app': infoVersao('9.9.9')};
    c.notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(at.versaoNova, '9.9.9');
    expect(downloadsFeitos, 1);
    expect(at.erro, isNotNull);
    for (var i = 0; i < 5; i++) {
      c.notifyListeners();
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(downloadsFeitos, 1);
    // "Tentar de novo" (o clique) baixa na hora — e confere tamanho e SHA-256.
    falharDownload = false;
    await at.atualizarAgora().catchError((_) {});
    expect(downloadsFeitos, 2);
    expect(at.pronto, isNotNull);
    // ⚠️ No Windows o clique instalaria de verdade (PowerShell + sair do processo).
  }, skip: Platform.isWindows);
}
