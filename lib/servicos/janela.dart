// A janela do NN Conversas é NORMAL (redimensionável) e lembra o tamanho e a
// posição. Minimizar, fechar ou o botão "Minimizar" do topo a tiram da tela e
// deixam só o ícone ao lado do relógio (bandeja / barra de menus); clicar no
// ícone a traz de volta como estava. Sair do app só pelo menu do ícone.
//
// ⚠️ A posição guardada só é aplicada se cair num monitor que existe AGORA: com
// o notebook longe do segundo monitor, a janela abriria fora da tela e o app
// pareceria não abrir.
import 'dart:async';
import 'dart:ui';

import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import 'armazenamento.dart';

class Janela {
  static const tamanhoPadrao = Size(1280, 800);
  static const tamanhoMinimo = Size(960, 620);
  static const _pref = 'janela';

  static Armazenamento? arm;
  static bool _indoParaBandeja = false;
  static bool naBandeja = false;
  static bool _porCima = false;
  static Timer? _gravar;

  static bool get indoParaBandeja => _indoParaBandeja;

  /// Ao abrir: o tamanho e a posição da última vez (se ainda couberem num monitor).
  static Future<void> restaurar() async {
    final g = arm?.pref<Map>(_pref, const {}) ?? const {};
    final w = (g['w'] as num?)?.toDouble() ?? 0, h = (g['h'] as num?)?.toDouble() ?? 0;
    final x = (g['x'] as num?)?.toDouble(), y = (g['y'] as num?)?.toDouble();
    try {
      if (w >= tamanhoMinimo.width && h >= tamanhoMinimo.height && x != null && y != null && await _cabe(Rect.fromLTWH(x, y, w, h))) {
        await windowManager.setBounds(Rect.fromLTWH(x, y, w, h));
      } else {
        await windowManager.setSize(tamanhoPadrao);
        await windowManager.center();
      }
      if (g['max'] == true) await windowManager.maximize();
    } catch (_) {
      // sem gerenciador de janelas (teste): segue
    }
  }

  /// Pelo menos 200×100 da janela dentro de algum monitor.
  static Future<bool> _cabe(Rect r) async {
    try {
      final telas = await screenRetriever.getAllDisplays();
      for (final d in telas) {
        final pos = d.visiblePosition ?? Offset.zero;
        final tam = d.visibleSize ?? d.size;
        final i = r.intersect(Rect.fromLTWH(pos.dx, pos.dy, tam.width, tam.height));
        if (i.width >= 200 && i.height >= 100) return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// A janela mudou de tamanho ou de lugar: guarda (com folga, para não gravar a cada pixel).
  static void mudou() {
    _gravar?.cancel();
    _gravar = Timer(const Duration(milliseconds: 600), guardar);
  }

  static Future<void> guardar() async {
    final a = arm;
    if (a == null || naBandeja || _indoParaBandeja) return;
    try {
      if (!await windowManager.isVisible() || await windowManager.isMinimized()) return;
      final max = await windowManager.isMaximized();
      final antes = a.pref<Map>(_pref, const {});
      if (max) {
        a.definir(_pref, {...antes, 'max': true});
        return;
      }
      final b = await windowManager.getBounds();
      a.definir(_pref, {'x': b.left, 'y': b.top, 'w': b.width, 'h': b.height, 'max': false});
    } catch (_) {}
  }

  /// Traz a janela de volta (da bandeja, minimizada ou atrás de outras).
  static Future<void> mostrar() async {
    try {
      await windowManager.setSkipTaskbar(false);
      if (await windowManager.isMinimized()) await windowManager.restore();
      await windowManager.show();
      await windowManager.focus();
      naBandeja = false;
    } catch (_) {
      // sem gerenciador de janelas (teste): segue
    }
  }

  static Future<void> paraBandeja() async {
    if (_indoParaBandeja) return;
    await guardar();
    _indoParaBandeja = true;
    try {
      await windowManager.hide();
      await windowManager.setSkipTaskbar(true);
      naBandeja = true;
    } catch (_) {
    } finally {
      _indoParaBandeja = false;
    }
  }

  /// Comunicado: a janela volta e fica POR CIMA das outras até o "Entendi".
  static Future<void> chamarAtencao() async {
    await mostrar();
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
