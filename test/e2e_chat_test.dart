// Ponta a ponta do cliente do app contra a API REAL (front-controller de teste
// com banco descartável). Só roda com CALLAPP_E2E=1 e a API em CALLAPP_E2E_API
// (padrão http://127.0.0.1:8892); a aprovação do computador é feita pelo
// script indicado em CALLAPP_E2E_APROVAR (`php semear_dart.php aprovar <chave>`).
import 'dart:io';

import 'package:conecta_callcenter/api/cliente.dart';
import 'package:conecta_callcenter/telas/conversas/chat_api.dart';
import 'package:flutter_test/flutter_test.dart';

final _ligado = Platform.environment['CALLAPP_E2E'] == '1';
final _base = Platform.environment['CALLAPP_E2E_API'] ?? 'http://127.0.0.1:8892';
final _aprovar = Platform.environment['CALLAPP_E2E_APROVAR'] ?? '';

// PNG 1×1 válido.
const _png = [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01,
  0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0xF8, 0xCF, 0xC0, 0xF0, 0x1F, 0x00, 0x05, 0x00, 0x01, 0xFF, 0x89, 0x99, 0x3D, 0x1D, 0x00, 0x00,
  0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];

Future<Api> _entrar(String chave, String email) async {
  final api = Api(base: _base, chave: chave);
  final r = await api.post('/v1/callapp/login', {'email': email, 'senha': 'Senha#2026'}) as Map;
  api.token = r['token'].toString();
  return api;
}

void main() {
  late String chave;
  late Api um, dois;
  late ChatApi chatUm, chatDois;
  late int direta;
  late Mensagem enviada;

  setUpAll(() async {
    if (!_ligado) return;
    final sem = Api(base: _base);
    final r = await sem.post('/v1/callapp/computador', {'so': 'macos', 'nome': 'teste-e2e', 'versao': '1.0.0'}) as Map;
    chave = r['chave'].toString();
    final partes = _aprovar.split(' ');
    final p = await Process.run(partes.first, [...partes.skip(1), chave]);
    if (p.exitCode != 0) throw StateError('aprovação falhou: ${p.stderr}');
    um = await _entrar(chave, 'u9202@t.local');
    dois = await _entrar(chave, 'u9203@t.local');
    chatUm = ChatApi(um);
    chatDois = ChatApi(dois);
  });

  test('sem token: a sessão é exigida', () async {
    final api = Api(base: _base, chave: chave);
    await expectLater(api.get('/v1/callapp/chat/conversations'), throwsA(isA<ApiErro>().having((e) => e.status, 'status', 401)));
  }, skip: !_ligado);

  test('a lista de pessoas traz o outro tele atendente e não traz operadora', () async {
    final u = await chatUm.usuarios();
    final ids = u.map((x) => (x['id'] as num).toInt()).toSet();
    expect(ids, contains(9203));
    expect(ids, isNot(contains(9205)));
    expect(ids, isNot(contains(9202))); // eu mesmo
  }, skip: !_ligado);

  test('conversa direta + mensagem formatada com anexo', () async {
    direta = await chatUm.direta(9203);
    expect(direta, greaterThan(0));
    final dir = Directory.systemTemp.createTempSync('cae2e');
    final f = File('${dir.path}/print.png')..writeAsBytesSync(_png);
    enviada = await chatUm.enviar(direta, corpo: 'oi <b>forte</b><br><span class="im-cor-3">verde</span>', html: true, arquivos: [f]);
    expect(enviada.html, contains('<b>forte</b>'));
    expect(enviada.html, contains('im-cor-3'));
    expect(enviada.corpo, contains('forte'));
    expect(enviada.corpo, isNot(contains('<b>')));
    expect(enviada.anexos, hasLength(1));
    expect(enviada.anexos.first.imagem, isTrue);
    expect(enviada.anexos.first.url, startsWith('/v1/callapp/chat/attachment'));
    final bytes = await um.bytes(enviada.anexos.first.url);
    expect(bytes.length, greaterThan(20));
  }, skip: !_ligado);

  test('o outro lado recebe, com o HTML e o estado de leitura', () async {
    final r = await chatDois.mensagens(direta);
    final ms = (r['messages'] as List).map((m) => Mensagem.de((m as Map).cast<String, dynamic>())).toList();
    final m = ms.firstWhere((x) => x.id == enviada.id);
    expect(m.minha, isFalse);
    expect(m.html, contains('<b>forte</b>'));
    final leitura = EstadoLeitura.de(r['read_state']);
    // depois de o Dois consultar, para o Um a mensagem está LIDA
    final r2 = await chatUm.mensagens(direta, after: enviada.id - 1);
    expect(EstadoLeitura.de(r2['read_state']).tique(enviada.id, 9202), 2);
    expect(leitura.porPessoa.keys, containsAll([9202, 9203]));
  }, skip: !_ligado);

  test('reagir alterna; editar muda o texto e marca editada', () async {
    var reacoes = await chatDois.reagir(enviada.id, '👍');
    expect(reacoes.single.minha, isTrue);
    reacoes = await chatDois.reagir(enviada.id, '👍');
    expect(reacoes, isEmpty);
    final ed = await chatUm.editar(enviada.id, 'oi <i>corrigido</i>', true);
    expect(ed.editada, isTrue);
    expect(ed.html, contains('<i>corrigido</i>'));
    final r = await chatDois.mensagens(direta, after: enviada.id);
    final editadas = ((r['edited'] as List?) ?? []).map((m) => Mensagem.de((m as Map).cast<String, dynamic>())).toList();
    expect(editadas.any((m) => m.id == enviada.id), isTrue);
  }, skip: !_ligado);

  test('menção em mensagem formatada chega realçada a quem foi citado', () async {
    final m = await chatDois.enviar(direta, corpo: 'veja <b>isso</b> @Tel Um', html: true);
    final r = await chatUm.mensagens(direta, after: m.id - 1);
    final recebida = (r['messages'] as List).map((x) => Mensagem.de((x as Map).cast<String, dynamic>())).firstWhere((x) => x.id == m.id);
    expect(recebida.mencionaMim, isTrue);
    expect(recebida.html, contains('im-mention'));
  }, skip: !_ligado);

  test('encaminhar copia a mensagem (com o anexo) para outra pessoa', () async {
    final r = await chatUm.encaminhar([enviada.id], ['u9201']);
    expect((r['enviadas'] as num).toInt(), 1);
  }, skip: !_ligado);

  test('grupo: enquete, voto e quem votou só para admin', () async {
    final g = await chatUm.grupo('Equipe teste', [9203]);
    await chatUm.criarEnquete(g, 'Almoço?', ['Sim', 'Não'], false);
    final r = await chatDois.mensagens(g);
    final poll = (r['messages'] as List).map((x) => Mensagem.de((x as Map).cast<String, dynamic>())).firstWhere((x) => x.enquete != null).enquete!;
    final votada = await chatDois.votar(poll.id, poll.opcoes.first.id);
    expect(votada!.opcoes.first.minha, isTrue);
    expect(votada.total, 1);
    await expectLater(chatDois.votos(poll.id), throwsA(isA<ApiErro>().having((e) => e.status, 'status', 403)));
    final v = await chatUm.votos(poll.id); // o criador é administrador do grupo
    expect(v['total'], 1);
    final mem = await chatUm.membros(g);
    expect(mem['is_admin'], isTrue);
    await chatDois.sair(g);
    await expectLater(chatDois.mensagens(g), throwsA(isA<ApiErro>().having((e) => e.status, 'status', 404)));
  }, skip: !_ligado);

  test('galeria de arquivos e tempo real desligado no teste', () async {
    final a = await chatUm.arquivos(direta);
    expect(a.where((x) => x['is_image'] == true), isNotEmpty);
    final s = await chatUm.socket();
    expect(s['enabled'], isFalse);
  }, skip: !_ligado);

  test('lista de conversas: não lidas e prévia em texto puro', () async {
    await chatDois.enviar(direta, corpo: '<b>nova</b>', html: true);
    final l = await chatUm.conversas();
    final c = l.firstWhere((x) => x.id == direta);
    expect(c.naoLidas, greaterThan(0));
    expect(c.previa, 'nova');
    final fav = await chatUm.favoritar(direta);
    expect(fav, isTrue);
    await chatUm.ordemFavoritos([direta]);
  }, skip: !_ligado);
}
