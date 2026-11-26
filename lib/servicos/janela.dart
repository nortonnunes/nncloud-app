// A janela é SEMPRE tela cheia. Minimizar, fechar ou o botão "Minimizar" do topo
// a tiram da tela e deixam só o ícone ao lado do relógio (bandeja / barra de
// menus); clicar no ícone volta em tela cheia. Sair do app só pelo menu do ícone.
//
// ⚠️ No macOS a tela cheia é um "espaço" próprio: esconder a janela sem sair dela
// deixaria um espaço preto. Por isso a ordem é sair da tela cheia → esperar a
// animação → esconder. Na volta, mostrar → focar → tela cheia.
import 'dart:async';
import 'dart:io';

import 'package:window_manager/window_manager.dart';

class Janela {
  static bool _indoParaBandeja = false;
  static bool naBandeja = false;
  static bool _porCima = false;

  /// Quem sai da tela cheia sem ser pelo nosso "minimizar" (Esc, botão verde)
  /// volta para ela.
  static bool get indoParaBandeja => _indoParaBandeja;

  static Future<void> telaCheia() async {
    try {
      await windowManager.setSkipTaskbar(false);
      await windowManager.show();
      await windowManager.focus();
      if (!await windowManager.isFullScreen()) await windowManager.setFullScreen(true);
      naBandeja = false;
    } catch (_) {
      // sem gerenciador de janelas (teste): segue
    }
  }

  static Future<void> paraBandeja() async {
    if (_indoParaBandeja) return;
    _indoParaBandeja = true;
    try {
      if (await windowManager.isFullScreen()) {
        await windowManager.setFullScreen(false);
        // A animação de saída do macOS leva ~0,6 s; escondendo antes, fica o espaço preto.
        await Future<void>.delayed(Duration(milliseconds: Platform.isMacOS ? 750 : 150));
      }
      await windowManager.hide();
      await windowManager.setSkipTaskbar(true);
      naBandeja = true;
    } catch (_) {
    } finally {
      _indoParaBandeja = false;
    }
  }

  /// Comunicado: a janela volta em tela cheia e fica POR CIMA até o "Entendi".
  static Future<void> chamarAtencao() async {
    await telaCheia();
    try {
      if (!_porCima) {
        await windowManager.setAlwaysOnTop(true);
        _porCima = true;
      }
    } catch (_) {}
  }

  static Future<void> soltar() async {
    if (!_porCima) return;
    try {
      await windowManager.setAlwaysOnTop(false);
    } catch (_) {}
    _porCima = false;
  }
}
