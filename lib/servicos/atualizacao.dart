// Atualização AUTOMÁTICA do aplicativo (o molde é a do NN Cloud).
//
//   1. ao abrir e a cada 6 h: `GET /v1/callapp/app` — a versão publicada deste SO
//   2. maior que a instalada: baixa por `/v1/callapp/app/baixar` (com a chave do
//      computador) e CONFERE tamanho + SHA-256; o que não confere é apagado
//   3. troca —
//      Windows: o instalador roda em silêncio DEPOIS que o app sai (um PowerShell
//               escondido espera o processo terminar) e reabre o app; se ele falhar,
//               a versão que estava é reaberta.
//      macOS:   o .app novo sai do DMG, é CONFERIDO (assinatura, MESMO time, MESMO
//               bundle id, versão) e entra no lugar do antigo por um script que
//               espera o app sair — renomeações na mesma pasta, com volta atrás.
//      Linux:   o .deb exige administrador: o app abre o instalador do sistema.
//
// ⚠️ Instalar REINICIA o app. Com a janela à vista (alguém atendendo), a versão
// baixada espera: instala quando o app for para a bandeja, ao abrir, ou pelo botão
// "Atualizar agora". Nunca no meio do trabalho sem aviso.
import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../api/cliente.dart';
import '../config.dart';
import 'armazenamento.dart';
import 'controle.dart';
import 'janela.dart';
import 'notificacoes.dart';
import 'sistema.dart';

/// a > b? x.y.z comparados como NÚMEROS ("1.10.0" > "1.9.9"); o que vem depois de
/// "-" ou "+" não conta.
bool versaoMaior(String a, String b) {
  List<int> v(String s) {
    final base = s.trim().split(RegExp(r'[-+]')).first;
    final partes = base.split('.').map((x) => int.tryParse(x.trim()) ?? 0).toList();
    while (partes.length < 3) {
      partes.add(0);
    }
    return partes.take(3).toList();
  }

  final x = v(a), y = v(b);
  for (var i = 0; i < 3; i++) {
    if (x[i] != y[i]) return x[i] > y[i];
  }
  return false;
}

class ErroAtualizacao implements Exception {
  final String mensagem;
  const ErroAtualizacao(this.mensagem);
  @override
  String toString() => mensagem;
}

const _extensao = {'windows': '.exe', 'macos': '.dmg', 'linux': '.deb'};

/// Nome de arquivo seguro para o instalador (o servidor manda o nome publicado).
String nomeInstalador(String nome, String so, String versao) {
  final ext = _extensao[so] ?? '';
  var n = p.basename(nome.replaceAll('\\', '/')).replaceAll(RegExp(r'[^A-Za-z0-9._ -]'), '').trim();
  if (n.isEmpty || n.startsWith('.')) n = 'Conecta-Callcenter-${versao.replaceAll(RegExp(r'[^0-9A-Za-z.+-]'), '')}$ext';
  if (ext.isNotEmpty && !n.toLowerCase().endsWith(ext)) n = '$n$ext';
  return n;
}

void _apagar(FileSystemEntity e) {
  try {
    if (e.existsSync()) e.deleteSync(recursive: true);
  } catch (_) {}
}

// ===================================================================
// Windows
// ===================================================================

/// Os argumentos do `powershell.exe` que instala DEPOIS que o app (pid) sair.
/// ⚠️ Esperar a saída evita a corrida com o `AppMutex` do instalador e a caixa
/// "o programa está aberto" (que, com /SUPPRESSMSGBOXES, cancelaria). Nada de
/// /CLOSEAPPLICATIONS: ele fecharia OUTROS programas (o Explorer inclusive).
/// Instalador com erro → reabre a versão que estava (`exe`).
List<String> comandoWindows({required int pid, required String instalador, required String exe, required String log}) {
  String q(String s) => "'${s.replaceAll("'", "''")}'";
  final cmd = StringBuffer()
    ..write('Wait-Process -Id $pid -ErrorAction SilentlyContinue; ')
    ..write(r'$p = Start-Process -FilePath ')
    ..write(q(instalador))
    ..write(" -ArgumentList '/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/NOCLOSEAPPLICATIONS',")
    ..write(q('/LOG="$log"'))
    ..write(r' -Wait -PassThru; if ($p.ExitCode -ne 0) { Start-Process -FilePath ')
    ..write(q(exe))
    ..write(" -ArgumentList '--oculto' }");
  return ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-Command', cmd.toString()];
}

// ===================================================================
// macOS
// ===================================================================

/// O .app de um executável de macOS (".../Conecta Callcenter.app/Contents/MacOS/Conecta Callcenter").
String? bundleDoExecutavel(String exe) {
  final i = exe.indexOf('.app/Contents/MacOS/');
  return i < 0 ? null : exe.substring(0, i + 4);
}

/// Por que o app NÃO pode se trocar sozinho (null = pode). [gravavel] é o teste de
/// escrita (injetável nos testes).
String? motivoParaNaoTrocarMac(String? bundle, {required bool Function(String caminho) gravavel}) {
  if (bundle == null) return 'O app não está rodando de um aplicativo instalado. Baixe e instale a versão nova.';
  if (bundle.contains('/AppTranslocation/')) {
    return 'O app está rodando direto do instalador. Arraste-o para a pasta Aplicativos, abra de lá e tente de novo.';
  }
  if (!gravavel(p.posix.dirname(bundle)) || !gravavel(bundle)) {
    return 'Sem permissão para trocar o aplicativo em ${p.posix.dirname(bundle)}. Baixe e instale a versão nova.';
  }
  return null;
}

/// Onde o .app novo espera e onde o antigo fica durante a troca: na MESMA pasta do
/// app (renomear é instantâneo e não muda de disco).
(String novo, String antigo) caminhosTrocaMac(String bundle) {
  // Sempre POSIX: é caminho de macOS, e o teste roda também no Windows (barra invertida).
  final dir = p.posix.dirname(bundle), nome = p.posix.basename(bundle);
  return (p.posix.join(dir, '.$nome.novo'), p.posix.join(dir, '.$nome.antigo'));
}

String _aspasSh(String s) => "'${s.replaceAll("'", r"'\''")}'";

/// O script que troca o app depois que ele sair (pid) e o abre de novo.
/// [abrir]: o comando que reabre o app (nos testes, um que não faz nada).
String scriptTrocaMac(
        {required int pid, required String app, required String novo, required String antigo, required String log, String abrir = 'open'}) =>
    '''#!/bin/bash
# Conecta Callcenter: troca o aplicativo pela versão nova DEPOIS que a antiga sair.
APP=${_aspasSh(app)}
NOVO=${_aspasSh(novo)}
VELHO=${_aspasSh(antigo)}
exec >>${_aspasSh(log)} 2>&1
echo "\$(date) troca: esperando o app (pid $pid) sair"
for i in \$(seq 1 300); do kill -0 $pid 2>/dev/null || break; sleep 0.2; done
rm -rf "\$VELHO"
if mv "\$APP" "\$VELHO"; then
  if mv "\$NOVO" "\$APP"; then
    echo "\$(date) troca: ok"
    rm -rf "\$VELHO"
  else
    echo "\$(date) troca: falhou; a versão antiga volta"
    mv "\$VELHO" "\$APP"
  fi
else
  echo "\$(date) troca: não deu para tirar o app antigo do lugar"
fi
rm -rf "\$NOVO"
$abrir "\$APP" --args --oculto
''';

/// Executa um comando e devolve (código, saída + erro).
typedef Executor = Future<(int, String)> Function(String exe, List<String> args);

Future<(int, String)> executar(String exe, List<String> args) async {
  final r = await Process.run(exe, args);
  return (r.exitCode, '${r.stdout}${r.stderr}');
}

/// O time (TeamIdentifier) que assinou um .app; null = sem assinatura de time.
Future<String?> timeDaAssinatura(String app, {Executor run = executar}) async {
  final (c, saida) = await run('/usr/bin/codesign', ['-dv', app]);
  if (c != 0) return null;
  final m = RegExp(r'TeamIdentifier=(\S+)').firstMatch(saida);
  final t = m?.group(1);
  return t == null || t == 'not' ? null : t;
}

Future<String?> _plist(String app, String chave, Executor run) async {
  final (c, saida) = await run('/usr/bin/plutil', ['-extract', chave, 'raw', '-o', '-', p.posix.join(app, 'Contents', 'Info.plist')]);
  return c == 0 ? saida.trim() : null;
}

/// Tira o .app do DMG para [destino] e CONFERE contra o app que está rodando
/// ([atual]): assinatura válida, o MESMO time, o MESMO bundle id e a [versao]
/// esperada. Qualquer diferença: apaga e recusa.
Future<void> prepararAppMac(File dmg, {required String destino, required String atual, required String versao, Executor run = executar}) async {
  final montagem = Directory('${dmg.path}.montado');
  _apagar(Directory(destino));
  if (montagem.existsSync()) await run('/usr/bin/hdiutil', ['detach', montagem.path, '-force']);
  _apagar(montagem);
  montagem.createSync(recursive: true);
  var (c, saida) = await run('/usr/bin/hdiutil', ['attach', '-nobrowse', '-readonly', '-noautoopen', '-mountpoint', montagem.path, dmg.path]);
  if (c != 0) throw ErroAtualizacao('Não deu para abrir o instalador baixado ($saida).');
  try {
    final apps = montagem.listSync().whereType<Directory>().where((d) => d.path.endsWith('.app')).toList();
    if (apps.length != 1) throw const ErroAtualizacao('O instalador baixado não tem o aplicativo esperado.');
    (c, saida) = await run('/usr/bin/ditto', [apps.single.path, destino]);
    if (c != 0) throw ErroAtualizacao('Não deu para copiar a versão nova ($saida).');
  } finally {
    await run('/usr/bin/hdiutil', ['detach', montagem.path, '-force']);
    _apagar(montagem);
  }
  try {
    (c, saida) = await run('/usr/bin/codesign', ['--verify', '--deep', '--strict', destino]);
    if (c != 0) throw ErroAtualizacao('A assinatura da versão nova não confere ($saida).');
    final timeAtual = await timeDaAssinatura(atual, run: run), timeNovo = await timeDaAssinatura(destino, run: run);
    if (timeAtual == null || timeNovo != timeAtual) throw const ErroAtualizacao('A versão nova não foi assinada pelo mesmo desenvolvedor.');
    final idAtual = await _plist(atual, 'CFBundleIdentifier', run), idNovo = await _plist(destino, 'CFBundleIdentifier', run);
    if (idAtual == null || idNovo != idAtual) throw const ErroAtualizacao('A versão nova não é o mesmo aplicativo.');
    final v = await _plist(destino, 'CFBundleShortVersionString', run);
    if (v != versao) throw ErroAtualizacao('O instalador baixado é da versão $v, não da $versao.');
  } catch (_) {
    _apagar(Directory(destino));
    rethrow;
  }
}

/// Teste de escrita numa pasta (macOS/Linux): `test -w`.
bool gravavelPosix(String caminho) {
  try {
    return Process.runSync('/bin/test', ['-w', caminho]).exitCode == 0;
  } catch (_) {
    return false;
  }
}

/// SHA-256 de um arquivo, lido em blocos (instalador de 100 MB não vai para a memória).
Future<String> sha256Arquivo(File f) async => (await sha256.bind(f.openRead()).first).toString();

class Atualizador extends ChangeNotifier {
  final Controle c;
  final Armazenamento arm;
  final Notificacoes notif;
  Atualizador(this.c, this.arm, this.notif);

  Timer? _t;
  String? versaoNova;      // publicada e maior que a instalada
  File? pronto;            // baixada e conferida, esperando a hora de instalar
  String? erro;
  bool baixando = false;
  double progresso = 0;

  Directory get _pasta => Directory(p.join(arm.dados.path, 'atualizacao'));

  void iniciar() {
    unawaited(verificar());
    _t = Timer.periodic(AppConfig.cicloVersao, (_) => verificar());
  }

  /// Confere a versão publicada e baixa a nova. Silencioso quando está em dia.
  Future<void> verificar() async {
    if (baixando || pronto != null || c.api.chave == null) return;
    try {
      final r = await c.api.get('/v1/callapp/app') as Map;
      final info = r[AppConfig.so] as Map?;
      final v = info?['versao']?.toString();
      if (v == null || !versaoMaior(v, AppConfig.versao)) return;
      versaoNova = v;
      notifyListeners();
      await _baixar(info!.cast<String, dynamic>());
    } catch (_) {
      // sem rede ou sem versão: tenta na próxima volta
    }
  }

  Future<void> _baixar(Map<String, dynamic> info) async {
    baixando = true;
    erro = null;
    progresso = 0;
    notifyListeners();
    final versao = info['versao'].toString();
    final f = File(p.join(_pasta.path, nomeInstalador('${info['nome'] ?? ''}', AppConfig.so, versao)));
    try {
      _pasta.createSync(recursive: true);
      await c.api.baixar('/v1/callapp/app/baixar?so=${AppConfig.so}', f, progresso: (feito, total) {
        final t = total ?? (info['tamanho'] as num?)?.toInt() ?? 0;
        progresso = t > 0 ? feito / t : 0;
        notifyListeners();
      });
      final tam = (info['tamanho'] as num?)?.toInt() ?? 0;
      final hash = await sha256Arquivo(f);
      if ((tam > 0 && f.lengthSync() != tam) || hash != (info['sha256'] ?? '').toString().toLowerCase()) {
        _apagar(f);
        throw const ErroAtualizacao('O arquivo baixado não confere com o publicado. Tento de novo mais tarde.');
      }
      pronto = f;
      notifyListeners();
      // Na bandeja (ninguém usando) ou antes do login: instala já.
      if (Janela.naBandeja || c.fase != Fase.pronto) await instalar();
    } on ApiErro catch (e) {
      erro = e.mensagem;
    } on ErroAtualizacao catch (e) {
      erro = e.mensagem;
    } catch (e) {
      erro = 'A atualização falhou ($e).';
    } finally {
      baixando = false;
      notifyListeners();
    }
  }

  /// Chamado quando o app vai para a bandeja: é a hora certa de trocar.
  Future<void> talvezInstalar() async {
    if (pronto != null) await instalar();
  }

  /// Instala a versão baixada e reinicia o app.
  Future<void> instalar() async {
    final f = pronto;
    final v = versaoNova;
    if (f == null || v == null || !f.existsSync()) return;
    try {
      if (Platform.isWindows) {
        final log = p.join(_pasta.path, 'instalar.log');
        await Process.start('powershell.exe', comandoWindows(pid: pid, instalador: f.path, exe: Platform.resolvedExecutable, log: log),
            mode: ProcessStartMode.detached);
        await _sair();
      } else if (Platform.isMacOS) {
        final app = bundleDoExecutavel(Platform.resolvedExecutable);
        final motivo = motivoParaNaoTrocarMac(app, gravavel: gravavelPosix);
        if (motivo != null) throw ErroAtualizacao(motivo);
        final (novo, antigo) = caminhosTrocaMac(app!);
        await prepararAppMac(f, destino: novo, atual: app, versao: v);
        final script = File(p.join(_pasta.path, 'trocar.sh'))..writeAsStringSync(
            scriptTrocaMac(pid: pid, app: app, novo: novo, antigo: antigo, log: p.join(_pasta.path, 'troca.log')));
        await Process.run('/bin/chmod', ['700', script.path]);
        await Process.start('/bin/bash', [script.path], mode: ProcessStartMode.detached);
        await _sair();
      } else {
        // Linux: o .deb precisa de administrador — abre no instalador do sistema.
        await launchUrl(Uri.file(f.path));
        await notif.mostrar('Atualização', 'A versão $v foi baixada. Conclua a instalação na janela que abriu.');
        pronto = null;
      }
    } on ErroAtualizacao catch (e) {
      erro = e.mensagem;
      pronto = null;
      _apagar(f);
      notifyListeners();
    } catch (e) {
      erro = 'Não deu para instalar a versão nova ($e).';
      notifyListeners();
    }
  }

  Future<void> _sair() async {
    await InstanciaUnica.liberar();
    exit(0);
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }
}
