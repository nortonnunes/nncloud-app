// O que o aplicativo guarda no computador.
//
// ⚠️ O TOKEN vai para o chaveiro do sistema (Keychain no macOS, Gerenciador de
// Credenciais no Windows, Secret Service — GNOME Keyring/KWallet — no Linux),
// nunca para arquivo. A ÚNICA exceção é o Linux SEM chaveiro na sessão (gerenciador
// de janelas mínimo, sessão remota): aí o token vai para `token` na pasta do app,
// com permissão 600 (só o usuário lê) — sem isso o app não conectaria.
// No macOS usamos o chaveiro "de login" (`useDataProtectionKeyChain: false`), que não exige perfil de
// provisionamento — e continua valendo depois de um novo build assinado.
// As PREFERÊNCIAS (tema, notificações, pausas, proxy…) são um JSON comum.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class Armazenamento {
  static const _seguro = FlutterSecureStorage(
    mOptions: MacOsOptions(accountName: 'NN Cloud', useDataProtectionKeyChain: false),
    wOptions: WindowsOptions(),
  );
  static const _chaveToken = 'nncloud_token';

  late Directory dados;
  late File _arquivoPrefs;
  Map<String, dynamic> prefs = {};

  /// `base` só existe para os testes (sem o plugin do path_provider).
  Future<void> iniciar({Directory? base}) async {
    final suporte = base ?? await getApplicationSupportDirectory();
    dados = Directory(p.join(suporte.path, 'NN Cloud'))..createSync(recursive: true);
    _arquivoPrefs = File(p.join(dados.path, 'preferencias.json'));
    try {
      prefs = (jsonDecode(_arquivoPrefs.readAsStringSync()) as Map).cast<String, dynamic>();
    } catch (_) {
      prefs = {};
    }
  }

  T pref<T>(String chave, T padrao) {
    final v = prefs[chave];
    return v is T ? v : padrao;
  }

  void definir(String chave, Object? valor) {
    if (valor == null) {
      prefs.remove(chave);
    } else {
      prefs[chave] = valor;
    }
    final tmp = File('${_arquivoPrefs.path}.tmp')..writeAsStringSync(jsonEncode(prefs));
    tmp.renameSync(_arquivoPrefs.path);
  }

  /// Só na verificação automática (compilação de teste): o token fica na memória e o
  /// chaveiro de quem usa o computador não é tocado.
  String? tokenFixo;
  bool usarTokenFixo = false;

  Future<String?> token() async {
    if (usarTokenFixo) return tokenFixo;
    try {
      final t = await _seguro.read(key: _chaveToken);
      if (t != null) return t;
    } catch (_) {
      // Linux sem chaveiro: cai no arquivo
    }
    return Platform.isLinux ? _lerArquivoToken() : null;
  }

  File get _arquivoToken => File(p.join(dados.path, 'token'));

  String? _lerArquivoToken() {
    try {
      final t = _arquivoToken.readAsStringSync().trim();
      return t.isEmpty ? null : t;
    } catch (_) {
      return null;
    }
  }

  void _gravarArquivoToken(String t) {
    final tmp = File('${_arquivoToken.path}.tmp');
    tmp.writeAsStringSync('');
    Process.runSync('chmod', ['600', tmp.path]);   // antes de escrever o segredo
    tmp.writeAsStringSync(t);
    tmp.renameSync(_arquivoToken.path);
  }

  Future<void> gravarToken(String? t) async {
    if (usarTokenFixo) {
      tokenFixo = t;
      return;
    }
    if (t == null) {
      try {
        await _seguro.delete(key: _chaveToken);
      } catch (_) {
        if (!Platform.isLinux) rethrow;
      }
      if (Platform.isLinux && _arquivoToken.existsSync()) _arquivoToken.deleteSync();
      return;
    }
    try {
      await _seguro.write(key: _chaveToken, value: t);
      if (Platform.isLinux && _arquivoToken.existsSync()) _arquivoToken.deleteSync();
    } catch (_) {
      if (!Platform.isLinux) rethrow;
      _gravarArquivoToken(t);
    }
  }
}
