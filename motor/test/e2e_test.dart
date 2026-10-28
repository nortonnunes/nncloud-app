// PONTA A PONTA: dois "computadores" com o motor de verdade, contra a API PHP
// real (php -S api_public), o S3 falso e um MySQL descartável.
//
//   NCL_E2E=1 NCL_API=http://127.0.0.1:8782 NCL_PREPARAR="php …/tokens.php" dart test test/e2e_test.dart
//
// Sem NCL_E2E o teste é pulado (ele precisa dos servidores de teste no ar).
@Tags(['e2e'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:nncloud_motor/motor.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

final _ligado = Platform.environment['NCL_E2E'] == '1';

class Pc {
  final String nome;
  final Directory raiz, dados;
  final Api api;
  late Sincronizador s;
  late ConfigPar par;
  final eventos = <Evento>[];
  Pc(this.nome, String token, Directory base)
      : raiz = Directory(p.join(base.path, nome, 'NN Cloud'))..createSync(recursive: true),
        dados = Directory(p.join(base.path, nome, 'dados'))..createSync(recursive: true),
        api = Api(Platform.environment['NCL_API'] ?? 'http://127.0.0.1:8782', token: token) {
    novoSincronizador();
  }
  void novoSincronizador() => s = Sincronizador(api: api, dados: dados, computador: nome, aoEvento: eventos.add);
  /// Nos testes o "observador" é o próprio teste: marca a pasta antes do ciclo.
  Future<ResultadoPar> ciclo({bool observador = true}) async {
    if (observador) s.marcarSujo(par.id);
    return (await s.ciclo([par])).single;
  }
  File f(String rel) => File(p.join(raiz.path, rel));
  void escrever(String rel, List<int> bytes, {DateTime? quando}) {
    final x = f(rel)..parent.createSync(recursive: true);
    x.writeAsBytesSync(bytes);
    if (quando != null) x.setLastModifiedSync(quando);
  }
}

List<int> bytes(int n, int semente) => List<int>.generate(n, (i) => (i * 31 + semente) % 256);

void main() {
  if (!_ligado) {
    test('ponta a ponta', () {}, skip: 'precisa da API e do S3 de teste no ar: defina NCL_E2E=1');
    return;
  }
  late Pc pc1, pc2;
  late int espaco;
  late Directory base;

  setUpAll(() async {
    if (!_ligado) return;
    final prep = Platform.environment['NCL_PREPARAR']!.split(' ');
    final r = await Process.run(prep.first, prep.sublist(1));
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    final j = jsonDecode((r.stdout as String).trim().split('\n').last) as Map<String, dynamic>;
    espaco = j['espaco'] as int;
    base = Directory.systemTemp.createTempSync('ncl-e2e-');
    pc1 = Pc('NOTE-ANA', j['pc1'] as String, base);
    pc2 = Pc('DESKTOP-ANA', j['pc2'] as String, base);
    final p1 = await pc1.api.criarPar(espacoId: espaco, caminhoLocal: pc1.raiz.path, nome: 'NN Cloud');
    pc1.par = ConfigPar(id: p1['id'] as int, raiz: pc1.raiz.path, espacoId: espaco);
    final p2 = await pc2.api.criarPar(espacoId: espaco, caminhoLocal: pc2.raiz.path, nome: 'NN Cloud');
    pc2.par = ConfigPar(id: p2['id'] as int, raiz: pc2.raiz.path, espacoId: espaco);
  });

  tearDownAll(() {
    if (_ligado) base.deleteSync(recursive: true);
  });

  test('envia do PC 1 e baixa no PC 2 (pequeno, em partes, pastas, NFD, ignorados)', () async {
    pc1.escrever('Contratos/2026/proposta.pdf', bytes(5000, 1));
    pc1.escrever('Planilhas/grande.xlsx', bytes(9 * 1024 * 1024 + 77, 2));
    pc1.escrever('Relatório.txt', utf8.encode('olá'));   // nome em NFD, como o macOS entrega
    pc1.escrever('vazio.txt', []);
    pc1.escrever('.DS_Store', [1, 2, 3]);
    Directory(p.join(pc1.raiz.path, 'Vazia')).createSync();
    final r1 = await pc1.ciclo();
    expect(r1.estado, 'ok', reason: r1.mensagem);
    expect(r1.enviados, 4, reason: r1.problemas.join('; '));
    final r2 = await pc2.ciclo();
    expect(r2.estado, 'ok', reason: r2.mensagem);
    expect(r2.baixados, 4, reason: r2.problemas.join('; '));
    expect(pc2.f('Planilhas/grande.xlsx').readAsBytesSync(), bytes(9 * 1024 * 1024 + 77, 2));
    expect(pc2.f('Contratos/2026/proposta.pdf').readAsBytesSync(), bytes(5000, 1));
    expect(pc2.f('vazio.txt').lengthSync(), 0);
    expect(Directory(p.join(pc2.raiz.path, 'Vazia')).existsSync(), isTrue);
    expect(pc2.f('.DS_Store').existsSync(), isFalse);
    expect(pc2.f(nfc('Relatório.txt')).readAsStringSync(), 'olá');
  });

  test('ciclo sem mudança não transfere nada', () async {
    final a = await pc1.ciclo(), b = await pc2.ciclo();
    expect(a.enviados + a.baixados + b.enviados + b.baixados, 0);
  });

  test('sem aviso do observador e sem mudança na nuvem, nem varre', () async {
    final r = await pc1.ciclo(observador: false);
    expect(r.mensagem, 'nada mudou');
    pc2.escrever('so-no-pc2.txt', [7, 7, 7]);
    await pc2.ciclo();
    final r1 = await pc1.ciclo(observador: false);   // a nuvem mudou: varre e baixa
    expect(r1.baixados, 1);
  });

  test('alteração no PC 2 chega ao PC 1', () async {
    pc2.escrever('Contratos/2026/proposta.pdf', bytes(6000, 9), quando: DateTime.now().add(const Duration(seconds: 2)));
    expect((await pc2.ciclo()).enviados, 1);
    final r = await pc1.ciclo();
    expect(r.baixados, 1);
    expect(pc1.f('Contratos/2026/proposta.pdf').readAsBytesSync(), bytes(6000, 9));
  });

  test('mudou nos dois: cópia de conflito com o nome do computador, nada se perde', () async {
    pc1.escrever('Relatório.txt', utf8.encode('versão do note'), quando: DateTime.now().add(const Duration(seconds: 3)));
    pc2.escrever('Relatório.txt', utf8.encode('versão do desktop'), quando: DateTime.now().add(const Duration(seconds: 4)));
    await pc1.ciclo();
    final r2 = await pc2.ciclo();
    expect(r2.conflitos, 1, reason: r2.problemas.join('; '));
    await pc1.ciclo();
    await pc2.ciclo();
    for (final pc in [pc1, pc2]) {
      final nomes = pc.raiz.listSync().map((e) => nfc(p.basename(e.path))).where((n) => n.startsWith('Relatório')).toList()..sort();
      expect(nomes.length, 2, reason: '${pc.nome}: $nomes');
      expect(nomes.any((n) => n.contains('conflito de DESKTOP-ANA')), isTrue, reason: '$nomes');
      expect(pc.f('Relatório.txt').readAsStringSync(), 'versão do note');
    }
  });

  test('pasta renomeada no PC 1 é renomeada no PC 2 sem baixar de novo', () async {
    Directory(p.join(pc1.raiz.path, 'Planilhas')).renameSync(p.join(pc1.raiz.path, 'Planilhas 2026'));
    final r1 = await pc1.ciclo();
    expect(r1.enviados, 0);
    final r2 = await pc2.ciclo();
    expect(r2.baixados, 0, reason: 'movimento não pode virar download');
    expect(pc2.f('Planilhas 2026/grande.xlsx').existsSync(), isTrue);
    expect(Directory(p.join(pc2.raiz.path, 'Planilhas')).existsSync(), isFalse);
  });

  test('apagado no PC 2 vai para a lixeira da nuvem e para a lixeira LOCAL do PC 1', () async {
    pc2.f('vazio.txt').deleteSync();
    expect((await pc2.ciclo()).excluidos, 1);
    expect((await pc1.ciclo()).excluidos, 1);
    expect(pc1.f('vazio.txt').existsSync(), isFalse);
    final lix = Directory(p.join(pc1.raiz.path, pastaLixeiraLocal)).listSync(recursive: true).map((e) => p.basename(e.path));
    expect(lix, contains('vazio.txt'));
  });

  test('exclusão em massa espera confirmação, e só então apaga', () async {
    for (var i = 0; i < 60; i++) {
      pc1.escrever('Lote/a$i.txt', bytes(10 + i, i));
    }
    await pc1.ciclo();
    await pc2.ciclo();
    Directory(p.join(pc2.raiz.path, 'Lote')).deleteSync(recursive: true);
    // Pasta inteira apagada = UMA operação na nuvem, que não passa do limite.
    expect((await pc2.ciclo()).excluidos, 1);
    await pc1.ciclo();
    // Agora 60 arquivos soltos apagados um a um: passa do limite.
    for (var i = 0; i < 60; i++) {
      pc1.escrever('Solto$i.txt', bytes(5 + i, i));
    }
    await pc1.ciclo();
    await pc2.ciclo();
    for (var i = 0; i < 60; i++) {
      pc2.f('Solto$i.txt').deleteSync();
    }
    final r = await pc2.ciclo();
    expect(r.estado, 'aguardando_confirmacao');
    expect(r.exclusao?.naNuvem, 60);
    await pc1.ciclo();
    expect(pc1.f('Solto0.txt').existsSync(), isTrue, reason: 'nada pode ter sido apagado antes da confirmação');
    pc2.s.confirmarExclusoes(pc2.par.id);
    final r2 = await pc2.ciclo();
    expect(r2.excluidos, 60, reason: '${r2.estado} ${r2.mensagem}');
    // O freio vale nos DOIS sentidos: o PC 1 também pergunta antes de tirar 60 arquivos.
    final r3 = await pc1.ciclo();
    expect(r3.estado, 'aguardando_confirmacao');
    expect(pc1.f('Solto0.txt').existsSync(), isTrue);
    pc1.s.confirmarExclusoes(pc1.par.id);
    expect((await pc1.ciclo()).excluidos, 60);
    expect(pc1.f('Solto0.txt').existsSync(), isFalse);
  });

  test('pasta do computador sumiu: o par para e nada é apagado na nuvem', () async {
    final antes = (await pc1.api.arvore(pc1.par.id, 0))['itens'] as List;
    final movida = Directory('${pc2.raiz.path} (desmontada)');
    pc2.raiz.renameSync(movida.path);
    final r = await pc2.ciclo();
    expect(r.estado, 'erro');
    final depois = (await pc1.api.arvore(pc1.par.id, 0))['itens'] as List;
    expect(depois.length, antes.length);
    movida.renameSync(pc2.raiz.path);
    expect((await pc2.ciclo()).estado, 'ok');
  });

  test('diário perdido: junção segura (nada é apagado) e volta ao normal', () async {
    pc2.f('Relatório.txt').deleteSync();   // apagado com o diário "perdido": NÃO vai para a lixeira
    File(p.join(pc2.dados.path, 'pares', '${pc2.par.id}', 'diario.json')).deleteSync();
    pc2.novoSincronizador();
    final r = await pc2.ciclo();
    expect(r.estado, 'ok', reason: r.mensagem);
    expect(r.excluidos, 0);
    expect(pc2.f('Relatório.txt').existsSync(), isTrue, reason: 'na junção segura o que falta é restaurado');
    expect(r.enviados, 0, reason: 'o que já era igual não trafega');
    final r2 = await pc2.ciclo();
    expect(r2.enviados + r2.baixados + r2.excluidos, 0);
  });

  test('kill -9 no meio do ciclo, várias vezes: converge sem duplicar nem perder', () async {
    // Compila o executor de um ciclo (rodar pelo `dart run` mediria o tempo de compilação).
    final exe = p.join(base.path, 'um_ciclo');
    final comp = await Process.run(Platform.resolvedExecutable, ['compile', 'exe', 'test/bin/um_ciclo.dart', '-o', exe]);
    expect(comp.exitCode, 0, reason: '${comp.stdout}${comp.stderr}');
    final arquivos = <String, List<int>>{};
    for (var i = 0; i < 12; i++) {
      arquivos['Interrompido/arq$i.bin'] = bytes(i.isEven ? 3 * 1024 * 1024 + i : 900 + i, 40 + i);
    }
    arquivos['Interrompido/grande.bin'] = bytes(17 * 1024 * 1024 + 3, 99);   // 3 partes
    arquivos.forEach(pc1.escrever);
    final args = [pc1.api.base, pc1.api.token!, pc1.dados.path, pc1.raiz.path, '${pc1.par.id}', '$espaco', pc1.nome];
    for (final ms in [150, 400, 700, 1100, 1600]) {
      final pr = await Process.start(exe, args);
      await Future<void>.delayed(Duration(milliseconds: ms));
      pr.kill(ProcessSignal.sigkill);
      await pr.exitCode;
    }
    pc1.novoSincronizador();   // relê o diário do disco, como o app reaberto
    final r = await pc1.ciclo();
    expect(r.estado, 'ok', reason: '${r.mensagem} ${r.problemas}');
    final again = await pc1.ciclo();
    expect(again.enviados + again.baixados, 0, reason: 'convergiu');
    await pc2.ciclo();
    arquivos.forEach((rel, b) => expect(pc2.f(rel).readAsBytesSync(), b, reason: rel));
    final nomes = Directory(p.join(pc2.raiz.path, 'Interrompido')).listSync().map((e) => p.basename(e.path)).toList();
    expect(nomes.length, arquivos.length, reason: 'sem cópia duplicada nem de conflito: $nomes');
  });

  test('servidor fora do ar: offline, nada muda', () async {
    final fora = Sincronizador(api: Api('http://127.0.0.1:9', token: pc1.api.token), dados: pc1.dados, computador: 'x');
    pc1.escrever('offline.txt', [1, 2, 3]);
    final r = (await fora.ciclo([pc1.par])).single;
    expect(r.estado, 'offline');
    expect(pc1.f('offline.txt').existsSync(), isTrue);
    pc1.novoSincronizador();
    expect((await pc1.ciclo()).enviados, 1, reason: 'volta e envia');
  });

  test('histórico e base replicados no servidor', () async {
    final acoes = <dynamic>{};
    for (final pc in [pc1, pc2]) {   // o histórico é de CADA computador
      final h = await pc.api.pedir('GET', 'historico', query: {'limite': '500'}) as Map;
      acoes.addAll((h['linhas'] as List).map((l) => (l as Map)['acao']));
    }
    expect(acoes, containsAll(['enviado', 'baixado', 'conflito', 'renomeado', 'excluido_nuvem']));
    final b = await pc1.api.baseDoPar(pc1.par.id, 0);
    expect((b['itens'] as List).isNotEmpty, isTrue);
  });
}
