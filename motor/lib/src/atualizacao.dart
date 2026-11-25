// Atualização do APLICATIVO pelo próprio app ("Atualizar agora").
//
//   1. pede o instalador publicado (GET app/baixar: URL de 5 min, versão, impressão)
//   2. baixa para a pasta de dados e CONFERE tamanho + impressão (a do NN Cloud)
//   3. troca —
//      Windows: o instalador roda em silêncio DEPOIS que o app sai (um PowerShell
//               escondido espera o processo terminar) e o próprio instalador reabre
//               o app; se ele falhar, o PowerShell reabre a versão que estava.
//      macOS:   o .app novo sai do DMG, é CONFERIDO (assinatura, mesmo time, mesmo
//               bundle id, versão) e entra no lugar do antigo por um script que
//               espera o app sair — renomeações na MESMA pasta, com volta atrás.
//      Linux:   o .deb exige administrador: o app só abre o download.
//
// Aqui fica o que dá para testar sem janela; o app (lib/servicos/controle.dart)
// só chama na ordem e sai.
import 'dart:io';

import 'package:path/path.dart' as p;

import 'api.dart';
import 'impressao.dart';

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
  if (n.isEmpty || n.startsWith('.')) n = 'NN-Cloud-${versao.replaceAll(RegExp(r'[^0-9A-Za-z.+-]'), '')}$ext';
  if (ext.isNotEmpty && !n.toLowerCase().endsWith(ext)) n = '$n$ext';
  return n;
}

/// Baixa o instalador publicado de [so] para [pasta] e confere tamanho e impressão.
/// Devolve o arquivo e a versão. Arquivo que não confere é APAGADO.
Future<(File, String)> baixarInstalador(Api api, String so, Directory pasta,
    {void Function(int feito, int total)? progresso, Duration espera = const Duration(seconds: 2)}) async {
  final Map<String, dynamic> info;
  try {
    info = await api.appBaixar(so);
  } on ApiErro catch (e) {
    throw ErroAtualizacao(e.status == 404 ? 'Ainda não há uma versão publicada para este sistema.' : e.mensagem);
  }
  final url = info['url'] as String? ?? '';
  final total = (info['tamanho'] as num?)?.toInt() ?? 0;
  final esperada = (info['impressao'] as String? ?? '').toLowerCase();
  final versao = '${info['versao'] ?? ''}';
  if (url.isEmpty || esperada.isEmpty || versao.isEmpty) {
    throw const ErroAtualizacao('O servidor não informou a versão nova. Tente de novo mais tarde.');
  }
  pasta.createSync(recursive: true);
  final f = File(p.join(pasta.path, nomeInstalador('${info['nome'] ?? ''}', so, versao)));
  // Sem retomada: um 200 a um pedido de "continuar de onde parou" mandaria o arquivo
  // inteiro de novo. O instalador é pequeno; recomeçar é o mais seguro.
  for (var tentativa = 1;; tentativa++) {
    var feito = 0;
    final raf = f.openSync(mode: FileMode.write);
    int st;
    try {
      st = await api.baixarPara(url, raf, aoReceber: (n) {
        feito += n;
        progresso?.call(feito, total);
      });
    } finally {
      raf.closeSync();
    }
    if (st == 200) break;
    if (st != 0 || tentativa >= 3) {
      _apagar(f);
      throw ErroAtualizacao(st == 0 ? 'Sem conexão para baixar a versão nova. Tente de novo em instantes.' : 'O download da versão nova falhou (HTTP $st).');
    }
    await Future<void>.delayed(espera * tentativa);
  }
  final imp = await Impressao.deArquivo(f);
  if (imp == null || (total > 0 && imp.tamanho != total) || imp.hex.toLowerCase() != esperada) {
    _apagar(f);
    throw const ErroAtualizacao('O arquivo baixado não confere com o publicado. Tente de novo.');
  }
  return (f, versao);
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

/// O .app de um executável de macOS (".../NN Cloud.app/Contents/MacOS/NN Cloud").
String? bundleDoExecutavel(String exe) {
  final i = exe.indexOf('.app/Contents/MacOS/');
  return i < 0 ? null : exe.substring(0, i + 4);
}

/// Por que o app NÃO pode se trocar sozinho (null = pode). [gravavel] é o teste de
/// escrita (injetável nos testes).
String? motivoParaNaoTrocarMac(String? bundle, {required bool Function(String caminho) gravavel}) {
  if (bundle == null) return 'O NN Cloud não está rodando de um aplicativo instalado. Baixe e instale a versão nova.';
  if (bundle.contains('/AppTranslocation/')) {
    return 'O NN Cloud está rodando direto do instalador. Arraste-o para a pasta Aplicativos, abra de lá e tente de novo.';
  }
  if (!gravavel(p.dirname(bundle)) || !gravavel(bundle)) {
    return 'Sem permissão para trocar o aplicativo em ${p.dirname(bundle)}. Baixe e instale a versão nova.';
  }
  return null;
}

/// Onde o .app novo espera e onde o antigo fica durante a troca: na MESMA pasta do
/// app (renomear é instantâneo e não muda de disco).
(String novo, String antigo) caminhosTrocaMac(String bundle) {
  final dir = p.dirname(bundle), nome = p.basename(bundle);
  return (p.join(dir, '.$nome.novo'), p.join(dir, '.$nome.antigo'));
}

String _aspasSh(String s) => "'${s.replaceAll("'", r"'\''")}'";

/// O script que troca o app depois que ele sair (pid) e o abre de novo.
/// [abrir]: o comando que reabre o app (nos testes, um que não faz nada).
String scriptTrocaMac(
        {required int pid, required String app, required String novo, required String antigo, required String log, String abrir = 'open'}) =>
    '''#!/bin/bash
# NN Cloud: troca o aplicativo pela versão nova DEPOIS que a antiga sair.
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
  final (c, saida) = await run('/usr/bin/plutil', ['-extract', chave, 'raw', '-o', '-', p.join(app, 'Contents', 'Info.plist')]);
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
