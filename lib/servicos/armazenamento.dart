// O que o aplicativo guarda no computador.
//
// ⚠️ O TOKEN vai para o chaveiro do sistema (Keychain no macOS, Gerenciador de
// Credenciais no Windows), nunca para arquivo. No macOS usamos o chaveiro
// "de login" (`useDataProtectionKeyChain: false`), que não exige perfil de
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

  Future<String?> token() async {
    try {
      return await _seguro.read(key: _chaveToken);
    } catch (_) {
      return null;
    }
  }

  Future<void> gravarToken(String? t) async {
    if (t == null) {
      await _seguro.delete(key: _chaveToken);
    } else {
      await _seguro.write(key: _chaveToken, value: t);
    }
  }
}
