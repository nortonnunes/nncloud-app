// "Atualizar agora": comparar versões, baixar e conferir o instalador, decidir se o
// app pode se trocar e a troca do macOS (script de verdade, com apps de mentira).
//
//   dart test test/atualizacao_test.dart
// O teste com o DMG de verdade roda só no Mac e só se `build/instaladores/` tiver um
// DMG e `build/macos/.../NN Cloud.app` existir (gerados por scripts/empacotar-macos.sh).
import 'dart:convert';
import 'dart:io';

import 'package:nncloud_motor/motor.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Servidor falso: `GET /v1/cloud/app/baixar` e o arquivo em `/arquivo`.
class Servidor {
  late HttpServer s;
  List<int> conteudo = utf8.encode('instalador de mentira ' * 1000);
  String? impressao;          // null = a certa
  int statusArquivo = 200;
  int statusInfo = 200;
  int pedidosArquivo = 0;

  Future<void> iniciar() async {
    s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    s.listen((r) async {
      if (r.uri.path == '/v1/cloud/app/baixar') {
        r.response.statusCode = statusInfo;
        r.response.headers.contentType = ContentType.json;
        r.response.write(jsonEncode(statusInfo == 200
            ? {'data': {
                'url': 'http://127.0.0.1:${s.port}/arquivo', 'versao': '1.3.0', 'nome': '../NN-Cloud-1.3.0-Windows.exe',
                'tamanho': conteudo.length, 'impressao': impressao ?? Impressao.deBytes(conteudo).hex, 'expira_seg': 300}}
            : {'error': {'status': statusInfo, 'message': 'O instalador para este sistema ainda não foi publicado.'}}));
      } else if (r.uri.path == '/arquivo') {
        pedidosArquivo++;
        r.response.statusCode = statusArquivo;
        if (statusArquivo == 200) r.response.add(conteudo);
      } else {
        r.response.statusCode = 404;
      }
      await r.response.close();
    });
  }

  String get base => 'http://127.0.0.1:${s.port}';
}

void main() {
  group('versaoMaior', () {
    for (final (a, b, r) in [
      ('1.3.0', '1.2.3', true), ('1.2.3', '1.3.0', false), ('1.3.0', '1.3.0', false),
      ('1.10.0', '1.9.9', true), ('2.0', '1.99.99', true), ('1.3.0+7', '1.3.0', false), ('1.3.1-beta', '1.3.0', true),
    ]) {
      test('$a > $b = $r', () => expect(versaoMaior(a, b), r));
    }
  });

  test('nome do instalador: sem caminho, sem caracteres estranhos, com a extensão do sistema', () {
    expect(nomeInstalador('../../NN-Cloud-1.3.0-Windows.exe', 'windows', '1.3.0'), 'NN-Cloud-1.3.0-Windows.exe');
    expect(nomeInstalador('', 'macos', '1.3.0'), 'NN-Cloud-1.3.0.dmg');
    expect(nomeInstalador('NN Cloud', 'windows', '1.3.0'), 'NN Cloud.exe');
    expect(nomeInstalador('.escondido', 'linux', '1.3.0'), 'NN-Cloud-1.3.0.deb');
  });

  group('baixarInstalador', () {
    late Servidor srv;
    late Api api;
    late Directory pasta;
    setUp(() async {
      srv = Servidor();
      await srv.iniciar();
      api = Api(srv.base, token: 't');
      pasta = Directory.systemTemp.createTempSync('ncl_atu');
    });
    tearDown(() async {
      api.fechar();
      await srv.s.close(force: true);
      pasta.deleteSync(recursive: true);
    });

    test('baixa e confere: impressão certa', () async {
      var ultimo = 0;
      final (f, v) = await baixarInstalador(api, 'windows', pasta, progresso: (feito, _) => ultimo = feito);
      expect(v, '1.3.0');
      expect(p.basename(f.path), 'NN-Cloud-1.3.0-Windows.exe');
      expect(p.dirname(f.path), pasta.path, reason: 'o "../" do nome não sai da pasta');
      expect(f.readAsBytesSync(), srv.conteudo);
      expect(ultimo, srv.conteudo.length);
    });

    test('impressão errada: apaga o arquivo e recusa', () async {
      srv.impressao = 'f' * 64;
      await expectLater(baixarInstalador(api, 'windows', pasta), throwsA(isA<ErroAtualizacao>()));
      expect(pasta.listSync(), isEmpty);
    });

    test('nada publicado (404): mensagem clara', () async {
      srv.statusInfo = 404;
      await expectLater(baixarInstalador(api, 'macos', pasta),
          throwsA(isA<ErroAtualizacao>().having((e) => e.mensagem, 'mensagem', contains('Ainda não há'))));
    });

    test('link vencido (403): não insiste e apaga', () async {
      srv.statusArquivo = 403;
      await expectLater(baixarInstalador(api, 'windows', pasta, espera: Duration.zero),
          throwsA(isA<ErroAtualizacao>().having((e) => e.mensagem, 'mensagem', contains('403'))));
      expect(srv.pedidosArquivo, 1);
      expect(pasta.listSync(), isEmpty);
    });
  });

  test('Windows: espera o app sair, instala em silêncio sem fechar outros programas e reabre se falhar', () {
    final a = comandoWindows(pid: 4242, instalador: r"C:\Users\Bruna D'Avila\AppData\NN Cloud\atualizacao\NN-Cloud-1.3.0-Windows.exe",
        exe: r'C:\Users\x\AppData\Local\Programs\NN Cloud\nncloud.exe', log: r'C:\Users\x\AppData\NN Cloud\atualizacao\instalar.log');
    expect(a.take(7), ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-Command']);
    final c = a.last;
    expect(c, startsWith('Wait-Process -Id 4242 '));
    expect(c, contains("'/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/NOCLOSEAPPLICATIONS'"));
    expect(c, isNot(contains('/CLOSEAPPLICATIONS\'')));
    expect(c, contains(r"'C:\Users\Bruna D''Avila\AppData\NN Cloud\atualizacao\NN-Cloud-1.3.0-Windows.exe'"), reason: "aspas simples dobradas no PowerShell");
    expect(c, contains(r"""'/LOG="C:\Users\x\AppData\NN Cloud\atualizacao\instalar.log"'"""));
    expect(c, contains(r'-Wait -PassThru; if ($p.ExitCode -ne 0) { Start-Process -FilePath '));
    expect(c, endsWith("-ArgumentList '--oculto' }"));
  });

  group('macOS', () {
    test('o .app do executável', () {
      expect(bundleDoExecutavel('/Applications/NN Cloud.app/Contents/MacOS/NN Cloud'), '/Applications/NN Cloud.app');
      expect(bundleDoExecutavel('/usr/local/bin/nncloud'), isNull);
    });

    test('quando não dá para se trocar sozinho', () {
      expect(motivoParaNaoTrocarMac('/Applications/NN Cloud.app', gravavel: (_) => true), isNull);
      expect(motivoParaNaoTrocarMac(null, gravavel: (_) => true), contains('não está rodando'));
      expect(motivoParaNaoTrocarMac('/private/var/folders/x/AppTranslocation/ABC/d/NN Cloud.app', gravavel: (_) => true),
          contains('Aplicativos'));
      expect(motivoParaNaoTrocarMac('/Applications/NN Cloud.app', gravavel: (c) => c != '/Applications'), contains('Sem permissão'));
      expect(motivoParaNaoTrocarMac('/Applications/NN Cloud.app', gravavel: (c) => c != '/Applications/NN Cloud.app'), contains('Sem permissão'));
    });

    test('a troca e a volta atrás ficam na mesma pasta do app', () {
      final (novo, antigo) = caminhosTrocaMac('/Applications/NN Cloud.app');
      expect(novo, '/Applications/.NN Cloud.app.novo');
      expect(antigo, '/Applications/.NN Cloud.app.antigo');
    });

    group('script de troca (bash de verdade, apps de mentira)', () {
      late Directory d;
      late String app, novo, antigo, log;
      setUp(() {
        d = Directory.systemTemp.createTempSync("ncl troca d'aspas");
        app = p.join(d.path, 'NN Cloud.app');
        (novo, antigo) = caminhosTrocaMac(app);
        log = p.join(d.path, 'troca.log');
        Directory(app).createSync();
        File(p.join(app, 'versao')).writeAsStringSync('velho');
        Directory(novo).createSync();
        File(p.join(novo, 'versao')).writeAsStringSync('novo');
      });
      tearDown(() => d.deleteSync(recursive: true));

      Future<void> rodar(int pid) async {
        final s = File(p.join(d.path, 'trocar.sh'))
          ..writeAsStringSync(scriptTrocaMac(pid: pid, app: app, novo: novo, antigo: antigo, log: log, abrir: '/usr/bin/true'));
        final r = await Process.run('/bin/bash', [s.path]);
        expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      }

      test('espera o processo sair, troca e não deixa sobras', () async {
        final dorminhoco = await Process.start('/bin/sleep', ['1']);
        final t0 = DateTime.now();
        await rodar(dorminhoco.pid);
        expect(DateTime.now().difference(t0).inMilliseconds, greaterThan(500), reason: 'esperou o pid sair');
        expect(File(p.join(app, 'versao')).readAsStringSync(), 'novo');
        expect(Directory(novo).existsSync(), isFalse);
        expect(Directory(antigo).existsSync(), isFalse);
        expect(File(log).readAsStringSync(), contains('troca: ok'));
      }, testOn: 'mac-os || linux');

      test('sem o app novo: a versão antiga volta para o lugar', () async {
        Directory(novo).deleteSync(recursive: true);
        await rodar(999999);
        expect(File(p.join(app, 'versao')).readAsStringSync(), 'velho');
        expect(Directory(antigo).existsSync(), isFalse);
        expect(File(log).readAsStringSync(), contains('a versão antiga volta'));
      }, testOn: 'mac-os || linux');
    });

    // Com o DMG e o app gerados por scripts/empacotar-macos.sh (só no Mac de quem compila).
    final raiz = p.normalize(p.join(Directory.current.path, '..'));
    final dmgs = Directory(p.join(raiz, 'build', 'instaladores')).existsSync()
        ? Directory(p.join(raiz, 'build', 'instaladores')).listSync().whereType<File>().where((f) => f.path.endsWith('.dmg')).toList()
        : <File>[];
    final atual = p.join(raiz, 'build', 'macos', 'Build', 'Products', 'Release', 'NN Cloud.app');
    final pular = !Platform.isMacOS || dmgs.isEmpty || !Directory(atual).existsSync() ? 'sem DMG/app gerado neste computador' : null;

    test('DMG de verdade: tira o app, confere assinatura, time, bundle id e versão', () async {
      final dmg = dmgs.last;
      final versao = RegExp(r'NN-Cloud-([0-9.]+)\.dmg$').firstMatch(dmg.path)!.group(1)!;
      final tmp = Directory.systemTemp.createTempSync('ncl_dmg');
      try {
        final copia = dmg.copySync(p.join(tmp.path, 'x.dmg'));
        final destino = p.join(tmp.path, '.NN Cloud.app.novo');
        await prepararAppMac(copia, destino: destino, atual: atual, versao: versao);
        expect(File(p.join(destino, 'Contents', 'MacOS', 'NN Cloud')).existsSync(), isTrue);
        expect(await timeDaAssinatura(destino), isNotNull);
        // Versão diferente da esperada: recusa e não deixa o app copiado.
        await expectLater(prepararAppMac(copia, destino: destino, atual: atual, versao: '99.0.0'),
            throwsA(isA<ErroAtualizacao>().having((e) => e.mensagem, 'mensagem', contains('99.0.0'))));
        expect(Directory(destino).existsSync(), isFalse);
        expect(Directory('${copia.path}.montado').existsSync(), isFalse, reason: 'desmontou');
      } finally {
        tmp.deleteSync(recursive: true);
      }
    }, skip: pular, timeout: const Timeout(Duration(minutes: 2)));
  });
}
