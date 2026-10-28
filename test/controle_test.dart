// O CONTROLE do aplicativo contra a API PHP real, o S3 falso e o MySQL de
// teste: conectar pelo código, adicionar uma pasta, sincronizar e perceber um
// arquivo novo pelo observador de pastas.
//
//   NCL_E2E=1 NCL_API=http://127.0.0.1:8782 NCL_PREPARAR=…/prep_e2e.sh NCL_PHP_T=…/scratchpad/ncl/t flutter test test/controle_test.dart
//
// ⚠️ Sem `TestWidgetsFlutterBinding`: aquele binding troca o HttpClient por um
// falso que responde 400 a tudo.
import 'dart:async';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nncloud/servicos/armazenamento.dart';
import 'package:nncloud/servicos/controle.dart';
import 'package:nncloud/servicos/notificacoes.dart';
import 'package:path/path.dart' as p;

final _ligado = Platform.environment['NCL_E2E'] == '1';

Future<String> php(String script, List<String> args) async {
  final r = await Process.run('php', [p.join(Platform.environment['NCL_PHP_T']!, script), ...args],
      workingDirectory: '/Volumes/projetos/IA/saas.nortonnunes.com.br');
  if (r.exitCode != 0) throw StateError('${r.stdout}${r.stderr}');
  return (r.stdout as String).trim();
}

Future<void> ate(bool Function() cond, {Duration limite = const Duration(seconds: 40)}) async {
  final fim = DateTime.now().add(limite);
  while (!cond()) {
    if (DateTime.now().isAfter(fim)) throw TimeoutException('condição não atingida');
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
}

void main() {
  if (!_ligado) {
    test('controle', () {}, skip: 'precisa da API e do S3 de teste: defina NCL_E2E=1');
    return;
  }
  HttpOverrides.global = null;

  test('conecta pelo código, adiciona pasta, sincroniza e reage ao observador', () async {
    final prep = Platform.environment['NCL_PREPARAR']!;
    expect((await Process.run(prep, [])).exitCode, 0);
    FlutterSecureStorage.setMockInitialValues({});

    final base = Directory.systemTemp.createTempSync('ncl-app-');
    final arm = Armazenamento();
    await arm.iniciar(base: base);
    arm.definir('api', Platform.environment['NCL_API'] ?? 'http://127.0.0.1:8782');
    final c = Controle(arm, Notificacoes());

    await c.iniciar();
    expect(c.situacao, Situacao.desconectado, reason: 'sem token: tela de conectar');

    final conexao = c.conectar();
    await ate(() => c.codigo != null);
    expect(RegExp(r'^[A-Z]{4}-[A-Z]{4}$').hasMatch(c.codigo!), isTrue, reason: c.codigo);
    await php('aprovar.php', [c.codigo!]);
    await conexao;
    expect(c.situacao, isNot(Situacao.desconectado), reason: c.mensagem);
    expect(await arm.token(), startsWith('nncl_'), reason: 'token guardado no chaveiro');
    expect((c.eu?['pessoa'] as Map?)?['nome'], 'Ana Lima');

    final pasta = Directory(p.join(base.path, 'Documentos do App'))..createSync();
    File(p.join(pasta.path, 'primeiro.txt')).writeAsStringSync('olá do app');
    final erro = await c.adicionarPar(pasta.path, mesmoNome: true);
    expect(erro, isNull);
    expect(c.pares.single['raiz_nome'], 'Documentos do App');
    await ate(() => c.resultados.isNotEmpty && c.situacao == Situacao.ok);
    expect(await php('conferir.php', ['primeiro.txt']), '1');

    // O observador percebe o arquivo novo e antecipa o ciclo (3 s depois).
    File(p.join(pasta.path, 'segundo.txt')).writeAsStringSync('chegou pelo observador');
    await ate(() => c.atividade.any((a) => a.caminho == 'segundo.txt' && a.tipo == 'enviado'));
    expect(await php('conferir.php', ['segundo.txt']), '1');

    // Pausar: o ciclo não envia; retomar: envia.
    await c.pausar(true);
    File(p.join(pasta.path, 'pausado.txt')).writeAsStringSync('espera');
    await Future<void>.delayed(const Duration(seconds: 5));
    expect(await php('conferir.php', ['pausado.txt']), '0');
    await c.pausar(false);
    await ate(() => c.atividade.any((a) => a.caminho == 'pausado.txt'));

    // Parar de sincronizar: os arquivos ficam nos dois lados.
    expect(await c.removerPar(c.pares.single['id'] as int), isNull);
    expect(File(p.join(pasta.path, 'primeiro.txt')).existsSync(), isTrue);
    expect(await php('conferir.php', ['primeiro.txt']), '1');

    await c.desconectar();
    expect(await arm.token(), isNull);
    expect(c.situacao, Situacao.desconectado);
    c.dispose();
    base.deleteSync(recursive: true);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
