// As cores do app vêm do NN Conecta (`GET /v1/callapp/aparencia`): as de
// Configurações → CSS, o tema sazonal no ar e o degradê da barra do menu — nos
// modos claro e escuro. Mudou lá, muda aqui na próxima consulta (10 min ou ao
// voltar da bandeja). Sem resposta, valem os padrões abaixo (os do site hoje).
import 'package:flutter/material.dart';

Color corHex(Object? v, Color padrao) {
  final s = (v ?? '').toString().trim();
  final m = RegExp(r'^#([0-9a-fA-F]{6})$').firstMatch(s);
  return m == null ? padrao : Color(0xFF000000 | int.parse(m.group(1)!, radix: 16));
}

/// Branco ou tinta escura sobre uma cor, pelo contraste (o mesmo critério do site).
Color tintaSobre(Color fundo) => fundo.computeLuminance() > 0.45 ? const Color(0xFF1B1416) : Colors.white;

class Paleta {
  final Color primary, primaryHover, bg, card, cardBorder, surface, text, muted, success, danger;
  final Color topoIni, topoFim;
  const Paleta({
    required this.primary,
    required this.primaryHover,
    required this.bg,
    required this.card,
    required this.cardBorder,
    required this.surface,
    required this.text,
    required this.muted,
    required this.success,
    required this.danger,
    required this.topoIni,
    required this.topoFim,
  });

  static const claroPadrao = Paleta(
    primary: Color(0xFF993635), primaryHover: Color(0xFF632324), bg: Color(0xFFF1ECEC), card: Colors.white,
    cardBorder: Color(0xFFECE3E3), surface: Color(0xFFF8F4F4), text: Color(0xFF2B1F1F), muted: Color(0xFF857374),
    success: Color(0xFF12A150), danger: Color(0xFFC0362F), topoIni: Color(0xFF1552D0), topoFim: Color(0xFF00AF52),
  );
  static const escuroPadrao = Paleta(
    primary: Color(0xFFBA7676), primaryHover: Color(0xFFC79393), bg: Color(0xFF171213), card: Color(0xFF211A1B),
    cardBorder: Color(0xFF382C2D), surface: Color(0xFF2A2122), text: Color(0xFFECE5E5), muted: Color(0xFFA2908F),
    success: Color(0xFF35C46F), danger: Color(0xFFE2645C), topoIni: Color(0xFF323232), topoFim: Color(0xFF323232),
  );

  factory Paleta.de(Map? cores, Map? topo, Paleta p) {
    final c = cores ?? const {};
    final t = topo ?? const {};
    return Paleta(
      primary: corHex(c['primary'], p.primary),
      primaryHover: corHex(c['primary_hover'], p.primaryHover),
      bg: corHex(c['bg'], p.bg),
      card: corHex(c['card'], p.card),
      cardBorder: corHex(c['card_border'], p.cardBorder),
      surface: corHex(c['surface'], p.surface),
      text: corHex(c['text'], p.text),
      muted: corHex(c['muted'], p.muted),
      success: corHex(c['success'], p.success),
      danger: corHex(c['danger'], p.danger),
      topoIni: corHex(t['ini'], p.topoIni),
      topoFim: corHex(t['fim'], p.topoFim),
    );
  }
}

/// Extensão do tema: o que não cabe no `ColorScheme` (borda do cartão, barra do topo…).
class CoresApp extends ThemeExtension<CoresApp> {
  final Paleta p;
  final List<Color> news;
  const CoresApp(this.p, this.news);

  Color corNews(int i) => news.isEmpty ? p.primary : news[(i >= 0 && i < news.length) ? i : 0];

  @override
  CoresApp copyWith({Paleta? p, List<Color>? news}) => CoresApp(p ?? this.p, news ?? this.news);

  @override
  CoresApp lerp(ThemeExtension<CoresApp>? other, double t) => t < .5 ? this : (other as CoresApp? ?? this);
}

extension CoresDoTema on BuildContext {
  CoresApp get cores => Theme.of(this).extension<CoresApp>() ?? const CoresApp(Paleta.claroPadrao, []);
  Paleta get pal => cores.p;
}

ThemeData temaDe(Paleta p, Brightness b, List<Color> news) {
  final cs = ColorScheme(
    brightness: b,
    primary: p.primary,
    onPrimary: tintaSobre(p.primary),
    secondary: p.primaryHover,
    onSecondary: tintaSobre(p.primaryHover),
    error: p.danger,
    onError: tintaSobre(p.danger),
    surface: p.card,
    onSurface: p.text,
    surfaceContainerHighest: p.surface,
    onSurfaceVariant: p.muted,
    outline: p.cardBorder,
    outlineVariant: p.cardBorder,
  );
  final base = ThemeData(colorScheme: cs, useMaterial3: true, brightness: b);
  return base.copyWith(
    scaffoldBackgroundColor: p.bg,
    canvasColor: p.bg,
    dividerColor: p.cardBorder,
    extensions: [CoresApp(p, news)],
    cardTheme: CardThemeData(
      color: p.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: p.cardBorder)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surface,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: p.cardBorder)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: p.cardBorder)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: p.primary, width: 1.6)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.primary,
        foregroundColor: tintaSobre(p.primary),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.text,
        side: BorderSide(color: p.cardBorder),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    tooltipTheme: TooltipThemeData(waitDuration: const Duration(milliseconds: 500), textStyle: TextStyle(color: p.card), decoration: BoxDecoration(color: p.text, borderRadius: BorderRadius.circular(6))),
    textTheme: base.textTheme.apply(bodyColor: p.text, displayColor: p.text),
  );
}
