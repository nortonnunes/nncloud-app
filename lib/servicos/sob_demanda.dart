// "NN Cloud" no Finder (macOS, File Provider): tudo aparece no Finder e só desce
// quando é aberto. Quem faz o trabalho é a extensão NNCloudFP (Swift); daqui o app
// só liga/desliga, entrega o endereço e o token e avisa que há mudanças.
// No Windows (Cloud Files) a mesma tela usa outro canal — fase seguinte.
import 'dart:io';

import 'package:flutter/services.dart';

class SobDemanda {
  static const _canal = MethodChannel('nncloud/fp');

  static bool get plataforma => Platform.isMacOS;

  /// (suportado, ligado, aprovado). Sem o canal (macOS antigo ou teste): tudo false.
  /// `aprovado` = a pessoa ligou o NN Cloud em Ajustes do Sistema (exigido no macOS 15+).
  static Future<(bool, bool, bool)> estado() async {
    if (!plataforma) return (false, false, false);
    try {
      final r = await _canal.invokeMapMethod<String, dynamic>('estado');
      return (
        (r?['suportado'] as bool?) ?? false,
        (r?['ligado'] as bool?) ?? false,
        (r?['aprovado'] as bool?) ?? true,
      );
    } catch (_) {
      return (false, false, false);
    }
  }

  /// Abre Ajustes do Sistema → Itens de Início e Extensões (onde se aprova a extensão).
  static Future<void> abrirAjustes() async {
    try {
      await _canal.invokeMethod('ajustes');
    } catch (_) {}
  }

  /// null = ok; senão, a mensagem do erro.
  static Future<String?> ligar({required String api, required String token, required bool liberar}) async {
    try {
      await _canal.invokeMethod('ligar', {'api': api, 'token': token, 'liberar': liberar});
      return null;
    } on PlatformException catch (e) {
      return e.message ?? 'O macOS recusou ligar o NN Cloud no Finder.';
    } on MissingPluginException {
      return 'Este Mac não tem o NN Cloud no Finder (precisa do macOS 13 ou mais novo).';
    }
  }

  /// Devolve (erro, pastaGuardada): a pasta onde o macOS guardou o que não tinha subido.
  static Future<(String?, String?)> desligar() async {
    try {
      final r = await _canal.invokeMethod<String>('desligar');
      return (null, r == null || r == 'ok' ? null : r);
    } on PlatformException catch (e) {
      return (e.message ?? 'Não foi possível desligar.', null);
    } on MissingPluginException {
      return (null, null);
    }
  }

  static Future<void> credenciais({required String api, required String token, required bool liberar}) async {
    try {
      await _canal.invokeMethod('credenciais', {'api': api, 'token': token, 'liberar': liberar});
    } catch (_) {}
  }

  static Future<void> apagarCredenciais() async {
    try {
      await _canal.invokeMethod('apagarCredenciais');
    } catch (_) {}
  }

  static Future<void> sinalizar() async {
    try {
      await _canal.invokeMethod('sinalizar');
    } catch (_) {}
  }

  static Future<void> abrir() async {
    try {
      await _canal.invokeMethod('abrir');
    } catch (_) {}
  }
}
