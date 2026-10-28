import 'package:flutter/material.dart';

import 'config.dart';

/// Tema claro (azul da logo) e escuro (vinho), como o app NN Conecta.
/// Cor nova de tela sai do `colorScheme` ou de [Cores], nunca de hex solto.
class Tema {
  static ThemeData claro() => _base(Brightness.light, AppConfig.azulLogo);
  static ThemeData escuro() => _base(Brightness.dark, AppConfig.vinho);

  static ThemeData _base(Brightness b, Color semente) {
    final cs = ColorScheme.fromSeed(seedColor: semente, brightness: b);
    return ThemeData(
      useMaterial3: true,
      colorScheme: cs,
      scaffoldBackgroundColor: cs.surface,
      cardTheme: CardThemeData(
        color: cs.surfaceContainerLow,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      visualDensity: VisualDensity.standard,
    );
  }
}

class Cores {
  static Color fraco(BuildContext c) => Theme.of(c).colorScheme.onSurfaceVariant;

  /// `ok`, `alerta`, `erro` ou `neutro` — um tom por modo (o verde que se lê
  /// no claro some no escuro).
  static Color situacao(BuildContext c, String tipo) {
    final escuro = Theme.of(c).brightness == Brightness.dark;
    switch (tipo) {
      case 'ok':
        return escuro ? const Color(0xFF6FD69B) : const Color(0xFF1B7A43);
      case 'alerta':
        return escuro ? const Color(0xFFF2B866) : const Color(0xFF9A5A09);
      case 'erro':
        return escuro ? const Color(0xFFFF8A80) : const Color(0xFFB3261E);
      default:
        return fraco(c);
    }
  }
}
