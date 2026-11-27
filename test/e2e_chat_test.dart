// Ponta a ponta do app contra a API REAL (front-controller de teste com banco
// descartável). Só roda com CONVERSAS_E2E=1 e a API em CONVERSAS_E2E_API (padrão
// http://127.0.0.1:8893). Antes: `php preparar.php && php semear_dart.php` na
// pasta da suíte do servidor; o SMTP falso (tests/service/smtp_falso.php) precisa
// estar no ar para o teste do código por e-mail. O QR é aprovado com o token de
// app que `CONVERSAS_E2E_TOKEN` traz (o `semear_dart.php` o imprime).
//
// O LOGIN é feito pelo `Controle` do próprio app — o mesmo código das telas.
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nn_conversas/api/cliente.dart';
import 'package:nn_conversas/servicos/armazenamento.dart';
import 'package:nn_conversas/servicos/controle.dart';
import 'package:nn_conversas/telas/conversas/chat_api.dart';

final _ligado = Platform.environment['CONVERSAS_E2E'] == '1';
final _base = Platform.environment['CONVERSAS_E2E_API'] ?? 'http://127.0.0.1:8893';
final _tokenCelular = Platform.environment['CONVERSAS_E2E_TOKEN'] ?? '';
const _segredo = 'JBSWY3DPEHPK3PXP';

// PNG 1×1 válido.
const _png = [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01,
  0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0xF8, 0xCF, 0xC0, 0xF0, 0x1F, 0x00, 0x05, 0x00, 0x01, 0xFF, 0x89, 0x99, 0x3D, 0x1D, 0x00, 0x00,
  0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];

/// O código do app autenticador (RFC 6238: SHA-1, 30 s, 6 dígitos).
String totp(String base32) {
  const alfabeto = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  var bits = 0, valor = 0;
  final chave = <int>[];
  for (final ch in base32.toUpperCase().replaceAll('=', '').split('')) {
    valor = (valor << 5) | alfabeto.indexOf(ch);
    bits += 5;
    if (bits >= 8) {
      chave.add((valor >> (bits - 8)) & 0xff);
      bits -= 8;
    }
  }
  final passo = DateTime.now().millisecondsSinceEpoch ~/ 1000 ~/ 30;
  final msg = ByteData(8)..setUint64(0, passo);
  final h = Hmac(sha1, chave).convert(msg.buffer.asUint8List()).bytes;
  final o = h.last & 0x0f;
  final n = ((h[o] & 0x7f) << 24) | (h[o + 1] << 16) | (h[o + 2] << 8) | h[o + 3];
  return (n % 1000000).toString().padLeft(6, '0');
}

Future<Controle> _controle() async {
  final arm = Armazenamento()..usarTokenFixo = true;
  await arm.iniciar(base: Directory.systemTemp.createTempSync('cv_e2e'));
  final c = Controle(arm, api: Api(base: _base));
  await c.iniciar();
  return c;
}

/// O último código de 6 dígitos que o SMTP falso recebeu para [para].
String _codigoDoEmail(String para) {
  final dir = Directory('${Directory.systemTemp.path}/svc_smtp');
  final fs = dir.existsSync() ? (dir.listSync().whereType<File>().where((f) => f.path.endsWith('.eml')).toList()..sort((a, b) => b.path.compareTo(a.path))) : <File>[];
  for (final f in fs) {
    final t = f.readAsStringSync();
    if (!t.contains(para)) continue;
    final m = RegExp(r'(?<![\d#])(\d{6})(?!\d)').allMatches(t.replaceAll('=\r\n', '').replaceAll('=\n', ''));
    for (final x in m) {
      if (x.group(1) != '000000') return x.group(1)!;
    }
  }
  return '';
}

void main() {
  late Controle ana, caio;
  late ChatApi chatAna, chatCaio;
  late int direta;
  late Mensagem enviada;

  group('login', () {
    test('senha errada: a mensagem genérica do site', () async {
      final c = await _controle();
      expect(c.fase, Fase.login);
      final e = await c.entrar('u9301@t.local', 'errada');
      expect(e, 'E-mail ou senha incorretos.');
      expect(c.etapa, EtapaLogin.senha);
    }, skip: !_ligado);

    test('com 2FA: senha → código do app autenticador → Conversas', () async {
      ana = await _controle();
      expect(await ana.entrar('u9301@t.local', 'Senha#2026'), isNull);
      expect(ana.etapa, EtapaLogin.doisFatores);
      expect((ana.passo['email'] as Map)['destino'], contains('•'));
      expect(await ana.enviarCodigo('000000'), contains('Restam 4'));
      expect(ana.restamTentativas, 4);
      expect(await ana.enviarCodigo(totp(_segredo)), isNull);
      expect(ana.fase, Fase.pronto);
      expect(ana.api.token, startsWith('nnconv_'));
      expect(await ana.arm.token(), ana.api.token);
      expect(ana.eu?['id'], 9301);
      expect(ana.podeCriarGrupo, isFalse);
    }, skip: !_ligado);

    test('isento de 2FA: entra só com a senha', () async {
      caio = await _controle();
      expect(await caio.entrar('u9303@t.local', 'Senha#2026'), isNull);
      expect(caio.fase, Fase.pronto);
      expect(caio.podeCriarGrupo, isTrue);
      expect(caio.podeNews, isTrue);
    }, skip: !_ligado);

    test('sem a política: aceita com CPF e segue para o 2FA', () async {
      final c = await _controle();
      await c.entrar('u9304@t.local', 'Senha#2026');
      expect(c.etapa, EtapaLogin.politica);
      expect((c.passo['titulo'] ?? '').toString(), isNotEmpty);
      expect(await c.aceitarPolitica('111.111.111-11'), isNotNull);
      expect(await c.aceitarPolitica('529.982.247-25'), isNull);
      expect(c.etapa, EtapaLogin.doisFatores);
      expect(await c.enviarCodigo(totp(_segredo)), isNull);
      expect(c.fase, Fase.pronto);
    }, skip: !_ligado);

    test('sem 2FA: configura o app autenticador e entra', () async {
      final c = await _controle();
      await c.entrar('u9302@t.local', 'Senha#2026');
      expect(c.etapa, EtapaLogin.setup);
      final seg = c.passo['segredo'].toString();
      expect((c.passo['uri'] ?? '').toString(), startsWith('otpauth://'));
      expect(await c.confirmarSetup(totp(seg)), isNull);
      expect(c.fase, Fase.pronto);
    }, skip: !_ligado);

    test('código por e-mail (SMTP falso)', () async {
      final c = await _controle();
      await c.entrar('u9309@t.local', 'Senha#2026');
      expect(c.etapa, EtapaLogin.doisFatores);
      final r = await c.pedirCodigoEmail();
      expect(r.ok, isTrue, reason: r.msg);
      expect(((c.passo['email'] as Map)['pendente'] as Map)['reenviar_em'], greaterThan(0));
      await Future<void>.delayed(const Duration(milliseconds: 400));
      final cod = _codigoDoEmail('u9309@t.local');
      expect(cod, hasLength(6));
      expect(await c.enviarCodigo(cod), isNull);
      expect(c.fase, Fase.pronto);
    }, skip: !_ligado);

    test('QR code aprovado no celular entra sem 2FA', () async {
      final c = await _controle();
      expect(await c.iniciarQr(), isNull);
      expect(c.etapa, EtapaLogin.qr);
      final payload = c.qr!['payload'].toString();
      expect(payload, startsWith('nnlogin:'));
      final cel = Api(base: _base, token: _tokenCelular);
      // O app do celular usa o /v1/qr/approve de sempre (o token do celular não é do NN Conversas).
      await cel.post('/v1/qr/approve', {'token': payload});
      for (var i = 0; i < 30 && c.fase != Fase.pronto; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
      expect(c.fase, Fase.pronto);
      expect(c.eu?['id'], 9301);
    }, skip: !_ligado || _tokenCelular.isEmpty);

    test('sair: a sessão deixa de valer', () async {
      final c = await _controle();
      await c.entrar('u9312@t.local', 'Senha#2026');
      if (c.etapa == EtapaLogin.politica) await c.aceitarPolitica('529.982.247-25');
      expect(c.fase, Fase.pronto);
      final tok = c.api.token!;
      await c.sair();
      expect(c.fase, Fase.login);
      await expectLater(Api(base: _base, token: tok).get('/v1/conversas/eu'),
          throwsA(isA<ApiErro>().having((e) => e.sessaoAcabou, 'sessaoAcabou', isTrue)));
    }, skip: !_ligado);
  });

  group('conversas', () {
    setUpAll(() {
      if (!_ligado) return;
      chatAna = ChatApi(ana.api);
      chatCaio = ChatApi(caio.api);
    });

    test('a lista de pessoas traz a equipe e não traz operadora', () async {
      final u = await chatAna.usuarios();
      final ids = u.map((x) => (x['id'] as num).toInt()).toSet();
      expect(ids, contains(9303));
      expect(ids, isNot(contains(9307)));
      expect(ids, isNot(contains(9301))); // eu mesma
    }, skip: !_ligado);

    test('conversa direta + mensagem formatada com anexo', () async {
      direta = await chatAna.direta(9303);
      expect(direta, greaterThan(0));
      final dir = Directory.systemTemp.createTempSync('cve2e');
      final f = File('${dir.path}/print.png')..writeAsBytesSync(_png);
      enviada = await chatAna.enviar(direta, corpo: 'oi <b>forte</b><br><span class="im-cor-3">verde</span>', html: true, arquivos: [f]);
      expect(enviada.html, contains('<b>forte</b>'));
      expect(enviada.corpo, isNot(contains('<b>')));
      expect(enviada.anexos, hasLength(1));
      expect(enviada.anexos.first.url, startsWith('/v1/conversas/chat/attachment'));
      final bytes = await caio.api.bytes(enviada.anexos.first.url);
      expect(bytes.length, greaterThan(20));
    }, skip: !_ligado);

    test('o outro lado recebe, com o HTML e o estado de leitura', () async {
      final r = await chatCaio.mensagens(direta);
      final ms = (r['messages'] as List).map((m) => Mensagem.de((m as Map).cast<String, dynamic>())).toList();
      final m = ms.firstWhere((x) => x.id == enviada.id);
      expect(m.minha, isFalse);
      final r2 = await chatAna.mensagens(direta, after: enviada.id - 1);
      expect(EstadoLeitura.de(r2['read_state']).tique(enviada.id, 9301), 2);
    }, skip: !_ligado);

    test('aviso de mensagem nova: a lista diz quem escreveu, e ler=0 não marca como lida', () async {
      final antes = (await chatAna.conversas()).firstWhere((c) => c.id == direta);
      final m = await chatCaio.enviar(direta, corpo: 'chegou agora', html: false);
      var c = (await chatAna.conversas()).firstWhere((c) => c.id == direta);
      expect(c.naoLidas, antes.naoLidas + 1);
      expect(c.ultimoId, m.id);
      expect(c.ultimoAutor, 'Caio Isento');
      // A conversa aberta com o app minimizado: busca, mas não marca.
      final r = await chatAna.mensagens(direta, after: m.id - 1, ler: false);
      expect((r['messages'] as List).map((x) => (x as Map)['id']), contains(m.id));
      c = (await chatAna.conversas()).firstWhere((c) => c.id == direta);
      expect(c.naoLidas, antes.naoLidas + 1, reason: 'ninguém leu');
      // Voltou a olhar: a consulta comum marca.
      await chatAna.mensagens(direta, after: m.id);
      c = (await chatAna.conversas()).firstWhere((c) => c.id == direta);
      expect(c.naoLidas, 0);
    }, skip: !_ligado);

    test('reagir e editar', () async {
      var reacoes = await chatCaio.reagir(enviada.id, '👍');
      expect(reacoes.single.minha, isTrue);
      final ed = await chatAna.editar(enviada.id, 'oi <i>corrigido</i>', true);
      expect(ed.editada, isTrue);
    }, skip: !_ligado);

    test('criar grupo: só com a permissão (como no site)', () async {
      await expectLater(chatAna.grupo('Sem permissão', [9303]), throwsA(isA<ApiErro>().having((e) => e.status, 'status', 403)));
      final g = await chatCaio.grupo('Equipe teste', [9301]);
      await chatCaio.criarEnquete(g, 'Almoço?', ['Sim', 'Não'], false);
      final r = await chatAna.mensagens(g);
      final poll = (r['messages'] as List).map((x) => Mensagem.de((x as Map).cast<String, dynamic>())).firstWhere((x) => x.enquete != null).enquete!;
      final votada = await chatAna.votar(poll.id, poll.opcoes.first.id);
      expect(votada!.total, 1);
      await chatAna.sair(g);
    }, skip: !_ligado);

    test('NN News: quem não tem a permissão leva 403', () async {
      await expectLater(ana.api.get('/v1/conversas/news'), throwsA(isA<ApiErro>().having((e) => e.status, 'status', 403)));
      final l = await caio.api.get('/v1/conversas/news');
      expect(l, isNotNull);
    }, skip: !_ligado);

    test('comunicados, avisos e início respondem', () async {
      await ana.verComunicados();
      expect(await ana.api.get('/v1/conversas/avisos'), isA<List>());
      final ini = await ana.api.get('/v1/conversas/inicio') as Map;
      expect(ini['news'], isNull); // a Ana não tem NN News
    }, skip: !_ligado);
  });

  // Reuniões do Google Meet: o Google é o falso da suíte do servidor
  // (google_falso.php); o `semear_dart.php` conecta a conta da Ana.
  group('reuniões do Meet', () {
    late Reuniao criada;
    String amanha() {
      final d = DateTime.now().add(const Duration(days: 1));
      return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    }

    test('status do Google: Ana pode criar, Caio não conectou', () async {
      expect((await chatAna.statusGoogle())['pode_criar'], isTrue);
      final st = await chatCaio.statusGoogle();
      expect(st['conectado'], isFalse);
      expect(st['conectar_url'], endsWith('/perfil?tab=integracoes'));
    }, skip: !_ligado);

    test('sem o Google conectado: 428', () async {
      await expectLater(chatCaio.criarReuniao(direta, agendar: false),
          throwsA(isA<ApiErro>().having((e) => e.status, 'status', 428)));
    }, skip: !_ligado);

    test('agendar: a reunião e a mensagem com o cartão', () async {
      final (r, m) = await chatAna.criarReuniao(direta, agendar: true, titulo: 'Pelo app', data: amanha(), hora: '10:00', duracao: 45, descricao: 'Pauta curta');
      expect(r, isNotNull);
      criada = r!;
      expect(criada.quando, 'Amanhã, 10:00–10:45');
      expect(criada.estado(), 'agendada');
      expect(criada.urlOk, isTrue);
      expect(criada.podeCancelarPor(9301), isTrue);
      expect(m?.reuniao?.id, criada.id);
      expect(m?.aindaEditavel, isFalse);
    }, skip: !_ligado);

    test('o outro lado vê o cartão, sem poder cancelar', () async {
      final r = await chatCaio.mensagens(direta);
      final m = (r['messages'] as List).map((x) => Mensagem.de((x as Map).cast<String, dynamic>())).firstWhere((x) => x.reuniao != null);
      expect(m.reuniao!.titulo, 'Pelo app');
      expect(m.reuniao!.podeCancelarPor(9303), isFalse);
      expect((await chatCaio.reunioes(direta)).map((x) => x.id), contains(criada.id));
      final prox = await chatCaio.proximasReunioes();
      expect(prox.firstWhere((x) => x.id == criada.id).conversa, isNotEmpty);
    }, skip: !_ligado);

    test('cancelar: só quem criou; o outro lado recebe pela consulta', () async {
      await expectLater(chatCaio.cancelarReuniao(criada.id), throwsA(isA<ApiErro>().having((e) => e.status, 'status', 403)));
      final (r, aviso) = await chatAna.cancelarReuniao(criada.id);
      expect(r!.estado(), 'cancelada');
      expect(aviso, isEmpty);
      final consulta = await chatCaio.mensagens(direta, after: criada.mensagemId);
      final ed = ((consulta['edited'] as List?) ?? const []).map((x) => Mensagem.de((x as Map).cast<String, dynamic>()));
      expect(ed.firstWhere((x) => x.id == criada.mensagemId).reuniao!.estado(), 'cancelada');
    }, skip: !_ligado);
  });
}
