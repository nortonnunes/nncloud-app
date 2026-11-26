// O que o aplicativo guarda no computador.
//
// ⚠️ O TOKEN vai para o chaveiro do sistema (Keychain no macOS, Gerenciador de
// Credenciais no Windows, Secret Service — GNOME Keyring/KWallet — no Linux),
// nunca para arquivo. A ÚNICA exceção é o Linux SEM chaveiro na sessão (gerenciador
// de janelas mínimo, sessão remota): aí o token vai para `token` na pasta do app,
// com permissão 600 (só o usuário lê) — sem isso o app não conectaria.
// No macOS usamos o chaveiro "de login" (`useDataProtectionKeyChain: false`), que não exige perfil de
// provisionamento — e continua valendo depois de um novo build assinado.
// Guarda também a CHAVE DO COMPUTADOR (`nncd_…`), do mesmo jeito que o token.
// As PREFERÊNCIAS (som, rascunhos, avisos já dados…) são um JSON comum.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class Armazenamento {
  static const _seguro = FlutterSecureStorage(
    mOptions: MacOsOptions(accountName: 'Conecta Callcenter', useDataProtectionKeyChain: false),
    wOptions: WindowsOptions(),
  );
  static const _chaveToken = 'callcenter_token';
  static const _chaveComputador = 'callcenter_computador';

  late Directory dados;
  late File _arquivoPrefs;
  Map<String, dynamic> prefs = {};

  /// `base` só existe para os testes (sem o plugin do path_provider).
  Future<void> iniciar({Directory? base}) async {
    final suporte = base ?? await getApplicationSupportDirectory();
    dados = Directory(p.join(suporte.path, 'Conecta Callcenter'))..createSync(recursive: true);
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

  /// Só nos testes: chave e token ficam na memória e o chaveiro não é tocado.
  bool usarTokenFixo = false;

  Future<String?> token() => _ler(_chaveToken, 'token');
  Future<void> gravarToken(String? t) => _gravar(_chaveToken, 'token', t);
  Future<String?> chaveComputador() => _ler(_chaveComputador, 'computador');
  Future<void> gravarChaveComputador(String? t) => _gravar(_chaveComputador, 'computador', t);

  final Map<String, String?> _memoria = {};

  Future<String?> _ler(String chave, String arquivo) async {
    if (usarTokenFixo) return _memoria[chave];
    try {
      final t = await _seguro.read(key: chave);
      if (t != null) return t;
    } catch (_) {
      // Linux sem chaveiro: cai no arquivo
    }
    return Platform.isLinux ? _lerArquivo(arquivo) : null;
  }

  File _arquivo(String nome) => File(p.join(dados.path, nome));

  String? _lerArquivo(String nome) {
    try {
      final t = _arquivo(nome).readAsStringSync().trim();
      return t.isEmpty ? null : t;
    } catch (_) {
      return null;
    }
  }

  void _gravarArquivo(String nome, String t) {
    final tmp = File('${_arquivo(nome).path}.tmp');
    tmp.writeAsStringSync('');
    Process.runSync('chmod', ['600', tmp.path]);   // antes de escrever o segredo
    tmp.writeAsStringSync(t);
    tmp.renameSync(_arquivo(nome).path);
  }

  Future<void> _gravar(String chave, String arquivo, String? t) async {
    if (usarTokenFixo) {
      _memoria[chave] = t;
      return;
    }
    final f = _arquivo(arquivo);
    if (t == null) {
      try {
        await _seguro.delete(key: chave);
      } catch (_) {
        if (!Platform.isLinux) rethrow;
      }
      if (Platform.isLinux && f.existsSync()) f.deleteSync();
      return;
    }
    try {
      await _seguro.write(key: chave, value: t);
      if (Platform.isLinux && f.existsSync()) f.deleteSync();
    } catch (_) {
      if (!Platform.isLinux) rethrow;
      _gravarArquivo(arquivo, t);
    }
  }
}
