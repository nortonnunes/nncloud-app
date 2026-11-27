// Atualização AUTOMÁTICA do aplicativo (o molde é a do NN Cloud).
//
//   1. a versão publicada deste SO chega no `/v1/callapp/eu` (consultado a cada
//      30 s com alguém logado) e, de reserva, pelo `GET /v1/callapp/app` ao abrir
//      e a cada 10 min (também antes do login). Publicou no NN Conecta = o app
//      percebe em até um minuto.
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
// nova aparece num AVISO (uma vez por versão) e num botão "Atualizar" no topo:
// quem decide a hora é a pessoa. Com o app na bandeja (ninguém olhando) ou antes
// do login, instala sozinho. Nunca no meio do trabalho sem aviso.
//
// ⚠️ Falhou (rede, arquivo que não confere)? Não tenta de novo a cada consulta do
// `/eu` — seriam dezenas de MB a cada 30 s: espera [esperaAposFalha] ou o clique
// em "Tentar de novo".
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
    final partes =
        base.split('.').map((x) => int.tryParse(x.trim()) ?? 0).toList();
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
  var n = p
      .basename(nome.replaceAll('\\', '/'))
      .replaceAll(RegExp(r'[^A-Za-z0-9._ -]'), '')
      .trim();
  if (n.isEmpty || n.startsWith('.')) {
    n = 'NN-Unifi-${versao.replaceAll(RegExp(r'[^0-9A-Za-z.+-]'), '')}$ext';
  }
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
List<String> comandoWindows(
    {required int pid,
    required String instalador,
    required String exe,
    required String log}) {
  String q(String s) => "'${s.replaceAll("'", "''")}'";
  final cmd = StringBuffer()
    ..write('Wait-Process -Id $pid -ErrorAction SilentlyContinue; ')
    ..write(r'$p = Start-Process -FilePath ')
    ..write(q(instalador))
    ..write(
        " -ArgumentList '/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/NOCLOSEAPPLICATIONS',")
    ..write(q('/LOG="$log"'))
    ..write(
        r' -Wait -PassThru; if ($p.ExitCode -ne 0) { Start-Process -FilePath ')
    ..write(q(exe))
    ..write(" -ArgumentList '--oculto' }");
  return [
    '-NoProfile',
    '-NonInteractive',
    '-ExecutionPolicy',
    'Bypass',
    '-WindowStyle',
    'Hidden',
    '-Command',
    cmd.toString()
  ];
}

// ===================================================================
// macOS
// ===================================================================

/// O .app de um executável de macOS (".../NN Unifi.app/Contents/MacOS/Conecta Callcenter").
String? bundleDoExecutavel(String exe) {
  final i = exe.indexOf('.app/Contents/MacOS/');
  return i < 0 ? null : exe.substring(0, i + 4);
}

/// Por que o app NÃO pode se trocar sozinho (null = pode). [gravavel] é o teste de
/// escrita (injetável nos testes).
String? motivoParaNaoTrocarMac(String? bundle,
    {required bool Function(String caminho) gravavel}) {
  if (bundle == null) {
    return 'O app não está rodando de um aplicativo instalado. Baixe e instale a versão nova.';
  }
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
        {required int pid,
        required String app,
        required String novo,
        required String antigo,
        required String log,
        String abrir = 'open'}) =>
    '''#!/bin/bash
# NN Unifi: troca o aplicativo pela versão nova DEPOIS que a antiga sair.
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
typedef Executor = Future<(int, String)> Function(
    String exe, List<String> args);

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
  final (c, saida) = await run('/usr/bin/plutil', [
    '-extract',
    chave,
    'raw',
    '-o',
    '-',
    p.posix.join(app, 'Contents', 'Info.plist')
  ]);
  return c == 0 ? saida.trim() : null;
}

/// Tira o .app do DMG para [destino] e CONFERE contra o app que está rodando
/// ([atual]): assinatura válida, o MESMO time, o MESMO bundle id e a [versao]
/// esperada. Qualquer diferença: apaga e recusa.
Future<void> prepararAppMac(File dmg,
    {required String destino,
    required String atual,
    required String versao,
    Executor run = executar}) async {
  final montagem = Directory('${dmg.path}.montado');
  _apagar(Directory(destino));
  if (montagem.existsSync()) {
    await run('/usr/bin/hdiutil', ['detach', montagem.path, '-force']);
  }
  _apagar(montagem);
  montagem.createSync(recursive: true);
  var (c, saida) = await run('/usr/bin/hdiutil', [
    'attach',
    '-nobrowse',
    '-readonly',
    '-noautoopen',
    '-mountpoint',
    montagem.path,
    dmg.path
  ]);
  if (c != 0) {
    throw ErroAtualizacao('Não deu para abrir o instalador baixado ($saida).');
  }
  try {
    final apps = montagem
        .listSync()
        .whereType<Directory>()
        .where((d) => d.path.endsWith('.app'))
        .toList();
    if (apps.length != 1) {
      throw const ErroAtualizacao(
          'O instalador baixado não tem o aplicativo esperado.');
    }
    (c, saida) = await run('/usr/bin/ditto', [apps.single.path, destino]);
    if (c != 0) {
      throw ErroAtualizacao('Não deu para copiar a versão nova ($saida).');
    }
  } finally {
    await run('/usr/bin/hdiutil', ['detach', montagem.path, '-force']);
    _apagar(montagem);
  }
  try {
    (c, saida) = await run(
        '/usr/bin/codesign', ['--verify', '--deep', '--strict', destino]);
    if (c != 0) {
      throw ErroAtualizacao(
          'A assinatura da versão nova não confere ($saida).');
    }
    final timeAtual = await timeDaAssinatura(atual, run: run),
        timeNovo = await timeDaAssinatura(destino, run: run);
    if (timeAtual == null || timeNovo != timeAtual) {
      throw const ErroAtualizacao(
          'A versão nova não foi assinada pelo mesmo desenvolvedor.');
    }
    final idAtual = await _plist(atual, 'CFBundleIdentifier', run),
        idNovo = await _plist(destino, 'CFBundleIdentifier', run);
    if (idAtual == null || idNovo != idAtual) {
      throw const ErroAtualizacao('A versão nova não é o mesmo aplicativo.');
    }
    final v = await _plist(destino, 'CFBundleShortVersionString', run);
    if (v != versao) {
      throw ErroAtualizacao(
          'O instalador baixado é da versão $v, não da $versao.');
    }
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
Future<String> sha256Arquivo(File f) async =>
    (await sha256.bind(f.openRead()).first).toString();

class Atualizador extends ChangeNotifier {
  final Controle c;
  final Armazenamento arm;
  final Notificacoes notif;
  Atualizador(this.c, this.arm, this.notif) {
    c.addListener(_aoMudarControle);
  }

  /// Depois de uma falha, a próxima tentativa sozinha espera isto.
  static const esperaAposFalha = Duration(minutes: 10);

  Timer? _t;
  String? versaoNova; // publicada e maior que a instalada
  Map<String, dynamic>?
      _info; // o que o servidor publicou (versao, nome, tamanho, sha256)
  File? pronto; // baixada e conferida, esperando a hora de instalar
  String? _prontoVersao;
  String? erro;
  bool baixando = false;
  bool instalando = false;
  double progresso = 0;

  /// O app não consegue se trocar sozinho (macOS fora de Aplicativos, Linux): o
  /// instalador baixado fica disponível para abrir à mão.
  bool manual = false;

  /// Instalar assim que terminar de baixar (a pessoa já clicou em "Atualizar").
  bool _instalarAoTerminar = false;
  String? _falhouVersao;
  DateTime? _falhouEm;

  Directory get _pasta => Directory(p.join(arm.dados.path, 'atualizacao'));

  /// Há versão nova (baixando, pronta ou com erro) — o topo mostra o botão.
  bool get temVersaoNova => versaoNova != null;

  void iniciar() {
    unawaited(verificar());
    _t = Timer.periodic(AppConfig.cicloVersao, (_) => verificar());
  }

  /// O `/eu` chegou: ele traz a versão publicada para o sistema deste computador.
  void _aoMudarControle() {
    final info = (c.eu?['app'] as Map?)?.cast<String, dynamic>();
    if (info != null) _novaInfo(info);
  }

  /// Confere a versão publicada (`GET /v1/callapp/app`). Silencioso quando está em dia.
  Future<void> verificar() async {
    if (c.api.chave == null) return;
    try {
      final r = await c.api.get('/v1/callapp/app') as Map;
      final info = (r[AppConfig.so] as Map?)?.cast<String, dynamic>();
      if (info != null) _novaInfo(info);
    } catch (_) {
      // sem rede, computador ainda não aprovado ou sem versão: tenta na próxima volta
    }
  }

  void _novaInfo(Map<String, dynamic> info, {bool forcar = false}) {
    final v = info['versao']?.toString();
    if (v == null || !versaoMaior(v, AppConfig.versao)) return;
    if (versaoNova != v) {
      // Versão nova (ou outra mais nova que a baixada): recomeça.
      versaoNova = v;
      _info = info;
      erro = null;
      manual = false;
      if (_prontoVersao != v) {
        if (pronto != null) _apagar(pronto!);
        pronto = null;
        _prontoVersao = null;
      }
      notifyListeners();
    }
    _info = info;
    if (baixando || instalando || (pronto != null && _prontoVersao == v)) {
      return;
    }
    if (!forcar &&
        _falhouVersao == v &&
        _falhouEm != null &&
        DateTime.now().difference(_falhouEm!) < esperaAposFalha) {
      return;
    }
    unawaited(_baixar(info));
  }

  /// O botão "Atualizar" (ou "Tentar de novo"): instala a baixada, ou baixa agora
  /// e instala ao terminar.
  Future<void> atualizarAgora() async {
    if (pronto != null && _prontoVersao == versaoNova) {
      await instalar();
      return;
    }
    _instalarAoTerminar = true;
    _falhouVersao = null;
    if (baixando) {
      notifyListeners();
      return;
    }
    final info = _info;
    if (info != null) {
      await _baixar(info);
    } else {
      await verificar();
    }
  }

  /// "Abrir o instalador": a instalação à mão (o app não conseguiu se trocar).
  Future<void> abrirInstalador() async {
    final f = pronto;
    if (f != null && f.existsSync()) await launchUrl(Uri.file(f.path));
  }

  Future<void> _baixar(Map<String, dynamic> info) async {
    baixando = true;
    erro = null;
    progresso = 0;
    notifyListeners();
    final versao = info['versao'].toString();
    final f = File(p.join(_pasta.path,
        nomeInstalador('${info['nome'] ?? ''}', AppConfig.so, versao)));
    var ok = false;
    try {
      _pasta.createSync(recursive: true);
      await c.api.baixar('/v1/callapp/app/baixar?so=${AppConfig.so}', f,
          progresso: (feito, total) {
        final t = total ?? (info['tamanho'] as num?)?.toInt() ?? 0;
        progresso = t > 0 ? feito / t : 0;
        notifyListeners();
      });
      final tam = (info['tamanho'] as num?)?.toInt() ?? 0;
      final hash = await sha256Arquivo(f);
      if ((tam > 0 && f.lengthSync() != tam) ||
          hash != (info['sha256'] ?? '').toString().toLowerCase()) {
        _apagar(f);
        throw const ErroAtualizacao(
            'O arquivo baixado não confere com o publicado. Tente de novo em alguns minutos.');
      }
      pronto = f;
      _prontoVersao = versao;
      ok = true;
    } on ApiErro catch (e) {
      erro = e.mensagem;
    } on ErroAtualizacao catch (e) {
      erro = e.mensagem;
    } catch (e) {
      erro = 'A atualização falhou ($e).';
    } finally {
      baixando = false;
      if (!ok) {
        _falhouVersao = versao;
        _falhouEm = DateTime.now();
        _instalarAoTerminar = false;
      }
      notifyListeners();
    }
    if (!ok) return;
    // A pessoa já pediu, ou ninguém está usando (bandeja / antes do login): instala já.
    if (_instalarAoTerminar || Janela.naBandeja || c.fase != Fase.pronto) {
      _instalarAoTerminar = false;
      await instalar();
    }
  }

  /// Chamado quando o app vai para a bandeja: é a hora certa de trocar.
  Future<void> talvezInstalar() async {
    if (pronto != null && !manual) await instalar();
  }

  /// Instala a versão baixada e reinicia o app.
  Future<void> instalar() async {
    final f = pronto;
    final v = _prontoVersao;
    if (f == null || v == null || !f.existsSync() || instalando) return;
    instalando = true;
    erro = null;
    notifyListeners();
    try {
      if (Platform.isWindows) {
        final log = p.join(_pasta.path, 'instalar.log');
        await Process.start(
            'powershell.exe',
            comandoWindows(
                pid: pid,
                instalador: f.path,
                exe: Platform.resolvedExecutable,
                log: log),
            mode: ProcessStartMode.detached);
        await _sair();
      } else if (Platform.isMacOS) {
        final app = bundleDoExecutavel(Platform.resolvedExecutable);
        final motivo = motivoParaNaoTrocarMac(app, gravavel: gravavelPosix);
        if (motivo != null) {
          // O instalador está certo; o lugar do app é que não deixa trocar. Fica
          // disponível para abrir à mão (arrastar para Aplicativos).
          erro = motivo;
          manual = true;
          return;
        }
        final (novo, antigo) = caminhosTrocaMac(app!);
        await prepararAppMac(f, destino: novo, atual: app, versao: v);
        final script = File(p.join(_pasta.path, 'trocar.sh'))
          ..writeAsStringSync(scriptTrocaMac(
              pid: pid,
              app: app,
              novo: novo,
              antigo: antigo,
              log: p.join(_pasta.path, 'troca.log')));
        await Process.run('/bin/chmod', ['700', script.path]);
        await Process.start('/bin/bash', [script.path],
            mode: ProcessStartMode.detached);
        await _sair();
      } else {
        // Linux: o .deb precisa de administrador — abre no instalador do sistema.
        manual = true;
        await launchUrl(Uri.file(f.path));
        await notif.mostrar('Atualização',
            'A versão $v foi baixada. Conclua a instalação na janela que abriu.');
      }
    } on ErroAtualizacao catch (e) {
      // A versão baixada não passou na conferência (assinatura, time, bundle):
      // nunca é instalada nem oferecida para abrir.
      erro = e.mensagem;
      pronto = null;
      _prontoVersao = null;
      _falhouVersao = v;
      _falhouEm = DateTime.now();
      _apagar(f);
    } catch (e) {
      erro = 'Não deu para instalar a versão nova ($e).';
    } finally {
      instalando = false;
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
    c.removeListener(_aoMudarControle);
    super.dispose();
  }
}
