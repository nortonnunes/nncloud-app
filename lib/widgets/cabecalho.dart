import 'package:flutter/material.dart';

import '../config.dart';

/// O cabeçalho de ondas do app NN Conecta: degradê azul → verde no claro,
/// escuro → vinho no escuro, com as ondas finas e a grade de pontos.
class Cabecalho extends StatelessWidget {
  final Widget filho;
  final double altura;
  const Cabecalho({super.key, required this.filho, this.altura = 168});

  @override
  Widget build(BuildContext context) {
    final escuro = Theme.of(context).brightness == Brightness.dark;
    final cores = escuro
        ? const [Color(0xFF2B2B2E), AppConfig.vinho]
        : const [AppConfig.degradeInicio, AppConfig.degradeFim];
    return ClipPath(
      clipper: _Curva(),
      child: Container(
        height: altura,
        decoration: BoxDecoration(gradient: LinearGradient(colors: cores, begin: Alignment.topLeft, end: Alignment.bottomRight)),
        child: CustomPaint(
          painter: const _Ondas(),
          child: Padding(padding: const EdgeInsets.fromLTRB(28, 22, 28, 40), child: filho),
        ),
      ),
    );
  }
}

class _Curva extends CustomClipper<Path> {
  @override
  Path getClip(Size s) => Path()
    ..lineTo(0, s.height - 34)
    ..quadraticBezierTo(s.width * 0.55, s.height - 22, s.width, s.height)
    ..lineTo(s.width, 0)
    ..close();

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _Ondas extends CustomPainter {
  const _Ondas();

  @override
  void paint(Canvas c, Size s) {
    final linha = Paint()
      ..color = Colors.white.withValues(alpha: 0.16)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (var k = 0; k < 4; k++) {
      final y = s.height * (0.22 + k * 0.13);
      final p = Path()..moveTo(-20, y);
      p.cubicTo(s.width * 0.3, y - 40, s.width * 0.55, y + 50, s.width + 20, y - 10 - k * 6);
      c.drawPath(p, linha);
    }
    final ponto = Paint()..color = Colors.white.withValues(alpha: 0.45);
    for (var i = 0; i < 6; i++) {
      for (var j = 0; j < 3; j++) {
        c.drawCircle(Offset(s.width - 120 + i * 16, 22 + j * 16), 1.6, ponto);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _Ondas old) => false;
}

/// Selo de situação (pílula com o texto na cor da situação sobre ela a 14%).
class Selo extends StatelessWidget {
  final String texto;
  final Color cor;
  final IconData? icone;
  const Selo(this.texto, this.cor, {super.key, this.icone});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: cor.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icone != null) ...[Icon(icone, size: 14, color: cor), const SizedBox(width: 5)],
          Text(texto, style: TextStyle(color: cor, fontWeight: FontWeight.w600, fontSize: 12.5)),
        ]),
      );
}

String bytesTexto(int b) {
  if (b >= 1073741824) return '${(b / 1073741824).toStringAsFixed(1).replaceAll('.', ',')} GB';
  if (b >= 1048576) return '${(b / 1048576).toStringAsFixed(1).replaceAll('.', ',')} MB';
  if (b >= 1024) return '${(b / 1024).round()} KB';
  return '$b bytes';
}
