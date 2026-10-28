// Integração com o sistema operacional: instância única, iniciar com o
// sistema e espaço livre em disco.
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:win32_registry/win32_registry.dart';

const _canal = MethodChannel('nncloud/sistema');

/// ⚠️ Um aplicativo só por pessoa no computador: dois sincronizando a mesma
/// pasta disputariam o mesmo diário. A trava é um arquivo bloqueado; a segunda
/// cópia avisa a primeira (por um socket local) para mostrar a janela e sai.
/// No Windows há também o MUTEX nomeado, que o instalador consulta para pedir
/// que o app seja fechado antes de atualizar.
class InstanciaUnica {
  static RandomAccessFile? _trava;
  static ServerSocket? _servidor;
  static const nomeMutex = 'NNCloudAppMutex';

  static Future<bool> garantir(Directory dados, void Function() aoChamar) async {
    dados.createSync(recursive: true);
    final raf = await File(p.join(dados.path, 'instancia.lock')).open(mode: FileMode.write);
    try {
      await raf.lock(FileLock.exclusive);
    } on FileSystemException {
      await raf.close();
      try {
        final porta = int.parse(File(p.join(dados.path, 'instancia.porta')).readAsStringSync().trim());
        final s = await Socket.connect(InternetAddress.loopbackIPv4, porta, timeout: const Duration(seconds: 2));
        s.write('mostrar\n');
        await s.flush();
        await s.close();
      } catch (_) {
        // a outra cópia não respondeu — mesmo assim, não abrimos uma segunda
      }
      return false;
    }
    _trava = raf;
    _servidor = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    File(p.join(dados.path, 'instancia.porta')).writeAsStringSync('${_servidor!.port}');
    _servidor!.listen((c) {
      c.listen((_) => aoChamar(), onDone: c.destroy, onError: (_) => c.destroy());
    });
    if (Platform.isWindows) _criarMutex();
    return true;
  }

  static void _criarMutex() {
    try {
      final k32 = DynamicLibrary.open('kernel32.dll');
      final criar = k32.lookupFunction<IntPtr Function(Pointer<Void>, Int32, Pointer<Utf16>), int Function(Pointer<Void>, int, Pointer<Utf16>)>(
          'CreateMutexW');
      final nome = nomeMutex.toNativeUtf16();
      criar(nullptr, 0, nome);   // fica aberto enquanto o processo vive
      malloc.free(nome);
    } catch (_) {
      // sem o mutex, o instalador só não consegue pedir para fechar o app
    }
  }

  static Future<void> liberar() async {
    await _servidor?.close();
    await _trava?.close();
  }
}

/// Iniciar junto com o sistema, em segundo plano (`--oculto`).
class InicioComSistema {
  static const _rotulo = 'br.com.nortonnunes.nncloud';
  static const _chaveRun = r'Software\Microsoft\Windows\CurrentVersion\Run';
  static const _valorRun = 'NN Cloud';

  static Future<bool> ativo() async {
    if (Platform.isMacOS) {
      try {
        final r = await _canal.invokeMethod<String>('estadoInicio');
        if (r == 'ativo') return true;
        if (r == 'inativo' || r == 'aprovacao') return false;
      } on MissingPluginException {
        // cai no LaunchAgent
      } on PlatformException {
        // idem
      }
      return File(_plist()).existsSync();
    }
    if (Platform.isWindows) {
      try {
        final k = Registry.openPath(RegistryHive.currentUser, path: _chaveRun);
        final v = k.getValueAsString(_valorRun);
        k.close();
        return v != null && v.isNotEmpty;
      } catch (_) {
        return false;
      }
    }
    return false;
  }

  /// Devolve a mensagem do que aconteceu (null = feito).
  static Future<String?> definir(bool ligar) async {
    if (Platform.isMacOS) {
      // macOS 13+: SMAppService (aparece em Ajustes → Geral → Itens de início).
      try {
        final r = await _canal.invokeMethod<String>('iniciarComSistema', {'ligar': ligar});
        if (r == 'ok') {
          _tirarPlist();
          return null;
        }
        if (r == 'aprovacao') return 'Autorize o NN Cloud em Ajustes do Sistema → Geral → Itens de início.';
      } on MissingPluginException {
        // versão antiga do macOS: LaunchAgent
      } on PlatformException {
        // idem
      }
      return _launchAgent(ligar);
    }
    if (Platform.isWindows) {
      try {
        final k = Registry.openPath(RegistryHive.currentUser, path: _chaveRun, desiredAccessRights: AccessRights.allAccess);
        if (ligar) {
          k.createValue(RegistryValue(_valorRun, RegistryValueType.string, '"${Platform.resolvedExecutable}" --oculto'));
        } else if (k.getValueAsString(_valorRun) != null) {
          k.deleteValue(_valorRun);
        }
        k.close();
        return null;
      } catch (e) {
        return 'Não foi possível alterar o início com o Windows ($e).';
      }
    }
    return 'Não disponível neste sistema.';
  }

  static String _plist() => p.join(Platform.environment['HOME'] ?? '', 'Library', 'LaunchAgents', '$_rotulo.plist');

  static void _tirarPlist() {
    final f = File(_plist());
    if (f.existsSync()) f.deleteSync();
  }

  static String? _launchAgent(bool ligar) {
    try {
      if (!ligar) {
        _tirarPlist();
        return null;
      }
      final exe = Platform.resolvedExecutable;
      File(_plist())
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$_rotulo</string>
  <key>ProgramArguments</key><array><string>${_xml(exe)}</string><string>--oculto</string></array>
  <key>RunAtLoad</key><true/>
  <key>ProcessType</key><string>Interactive</string>
</dict>
</plist>
''');
      return null;
    } catch (e) {
      return 'Não foi possível configurar o início com o macOS ($e).';
    }
  }

  static String _xml(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
}

/// Espaço livre no disco de uma pasta, em bytes (null = não deu para saber).
Future<int?> espacoLivre(String pasta) async {
  try {
    if (Platform.isWindows) {
      final k32 = DynamicLibrary.open('kernel32.dll');
      final f = k32.lookupFunction<Int32 Function(Pointer<Utf16>, Pointer<Uint64>, Pointer<Uint64>, Pointer<Uint64>),
          int Function(Pointer<Utf16>, Pointer<Uint64>, Pointer<Uint64>, Pointer<Uint64>)>('GetDiskFreeSpaceExW');
      final caminho = pasta.toNativeUtf16();
      final livre = calloc<Uint64>();
      try {
        if (f(caminho, livre, nullptr, nullptr) == 0) return null;
        return livre.value;
      } finally {
        malloc.free(caminho);
        calloc.free(livre);
      }
    }
    final r = await Process.run('df', ['-k', pasta]);
    final linhas = (r.stdout as String).trim().split('\n');
    if (linhas.length < 2) return null;
    final cols = linhas.last.split(RegExp(r'\s+'));
    return int.parse(cols[3]) * 1024;
  } catch (_) {
    return null;
  }
}

/// Pastas que NÃO podem ser a raiz de uma sincronização (ou motivo, ou null).
String? motivoPastaRecusada(String caminho, List<String> jaSincronizadas) {
  final c = p.normalize(p.absolute(caminho));
  final casa = p.normalize(Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '');
  bool igual(String a, String b) => Platform.isWindows || Platform.isMacOS ? a.toLowerCase() == b.toLowerCase() : a == b;
  bool dentro(String a, String b) => igual(a, b) || p.isWithin(Platform.isWindows || Platform.isMacOS ? b.toLowerCase() : b,
      Platform.isWindows || Platform.isMacOS ? a.toLowerCase() : a);
  if (p.rootPrefix(c) == c || c == '/') return 'Escolha uma pasta, não o disco inteiro.';
  if (casa.isNotEmpty && igual(c, casa)) return 'Escolha uma pasta dentro da sua pasta pessoal, não ela inteira.';
  final sistema = Platform.isWindows
      ? [r'C:\Windows', r'C:\Program Files', r'C:\Program Files (x86)', r'C:\ProgramData']
      : ['/System', '/Library', '/Applications', '/usr', '/bin', '/sbin', '/private', '/Volumes/Macintosh HD'];
  for (final s in sistema) {
    if (dentro(c, s)) return 'Pastas do sistema não podem ser sincronizadas.';
  }
  final baixo = c.toLowerCase();
  const outros = ['icloud drive', 'mobile documents', 'onedrive', 'dropbox', 'google drive', 'googledrive', 'cloudstorage'];
  for (final o in outros) {
    if (baixo.contains(o)) return 'Esta pasta já é sincronizada por outro serviço (iCloud, OneDrive, Dropbox ou Google Drive). Escolha outra.';
  }
  for (final j in jaSincronizadas) {
    final jn = p.normalize(j);
    if (dentro(c, jn) || dentro(jn, c)) return 'Esta pasta já está sincronizada (ou está dentro de outra que está).';
  }
  if (Platform.isWindows && c.startsWith(r'\\')) return 'rede';
  return null;
}
