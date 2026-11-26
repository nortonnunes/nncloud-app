// A barra do menu em ONDA, a mesma do NN Conecta (`body.menu-onda .topbar`):
// degradê da esquerda para a direita, ondas finas, grade de pontos e a borda de
// baixo curva — o caminho da máscara do site (`M0 0H100V100Q55 72 0 62Z`).
// As cores vêm do servidor (padrão, Configurações → CSS ou o tema sazonal), e a
// imagem do topo do tema sazonal entra por baixo das ondas.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../tema.dart';

Path caminhoOnda(Size s, double curva) {
  // A curva ocupa só a faixa de baixo; o resto é retângulo (onde ficam os links).
  final h = s.height;
  final base = h - curva;
  return Path()
    ..moveTo(0, 0)
    ..lineTo(s.width, 0)
    ..lineTo(s.width, h)
    ..quadraticBezierTo(s.width * .55, base + curva * .72, 0, base + curva * .62)
    ..close();
}

class _PintorOnda extends CustomPainter {
  final Color ini, fim;
  final bool escuro;
  final double curva;
  _PintorOnda(this.ini, this.fim, this.escuro, this.curva);

  @override
  void paint(Canvas canvas, Size s) {
    final forma = caminhoOnda(s, curva);
    canvas.save();
    canvas.clipPath(forma);
    final r = Offset.zero & s;
    canvas.drawRect(r, Paint()..shader = LinearGradient(colors: [ini, fim]).createShader(r));

    // Ondas finas (três), em branco translúcido.
    final linha = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.white.withValues(alpha: escuro ? .07 : .16);
    for (var k = 0; k < 3; k++) {
      final y0 = s.height * (.28 + k * .18);
      final p = Path()..moveTo(0, y0);
      for (double x = 0; x <= s.width; x += 8) {
        p.lineTo(x, y0 + math.sin((x / s.width) * math.pi * 2 * 1.5 + k * 1.3) * (7 + k * 3));
      }
      canvas.drawPath(p, linha);
    }

    // Grade de pontos na faixa curva (no site eles ficam ACIMA da curva).
    final ponto = Paint()..color = Colors.white.withValues(alpha: escuro ? .10 : .22);
    final topo = s.height - curva;
    for (double y = topo + 6; y < s.height - 4; y += 9) {
      for (double x = s.width * .62; x < s.width - 10; x += 9) {
        canvas.drawCircle(Offset(x, y), 1.1, ponto);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PintorOnda o) => o.ini != ini || o.fim != fim || o.escuro != escuro || o.curva != curva;
}

/// A barra em onda com o conteúdo (os links do menu) por cima.
class BarraOnda extends StatelessWidget {
  final Widget child;
  final String? fundo;   // imagem do topo do tema sazonal
  final double curva;
  const BarraOnda({super.key, required this.child, this.fundo, this.curva = 26});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final escuro = Theme.of(context).brightness == Brightness.dark;
    return CustomPaint(
      painter: _PintorOnda(p.topoIni, p.topoFim, escuro, curva),
      child: Stack(children: [
        if (fundo != null && fundo!.isNotEmpty)
          Positioned.fill(
            child: ClipPath(
              clipper: _Recorte(curva),
              child: Opacity(
                opacity: .35,
                child: Image.network(fundo!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
              ),
            ),
          ),
        Padding(padding: EdgeInsets.only(bottom: curva), child: child),
      ]),
    );
  }
}

class _Recorte extends CustomClipper<Path> {
  final double curva;
  _Recorte(this.curva);
  @override
  Path getClip(Size size) => caminhoOnda(size, curva);
  @override
  bool shouldReclip(covariant _Recorte o) => o.curva != curva;
}

/// Um link do menu na barra (branco, sublinhado quando é a tela aberta).
class LinkMenu extends StatelessWidget {
  final String rotulo;
  final IconData icone;
  final bool ativo;
  final int selo;
  final VoidCallback onTap;
  const LinkMenu({super.key, required this.rotulo, required this.icone, required this.ativo, required this.onTap, this.selo = 0});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: ativo ? Colors.white.withValues(alpha: .18) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icone, color: Colors.white, size: 19),
              const SizedBox(width: 8),
              Text(rotulo, style: TextStyle(color: Colors.white, fontWeight: ativo ? FontWeight.w700 : FontWeight.w600, fontSize: 14.5)),
              if (selo > 0) ...[
                const SizedBox(width: 7),
                Selo(selo, claro: true),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

class Selo extends StatelessWidget {
  final int n;
  final bool claro;
  const Selo(this.n, {super.key, this.claro = false});
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      constraints: const BoxConstraints(minWidth: 19),
      height: 19,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: claro ? Colors.white : p.danger, borderRadius: BorderRadius.circular(99)),
      child: Text(n > 99 ? '99+' : '$n',
          style: TextStyle(color: claro ? p.danger : Colors.white, fontSize: 11, fontWeight: FontWeight.w800, height: 1)),
    );
  }
}

/// As cores dos status (as do chat do site; cor nunca sozinha — vai com o rótulo).
Color corDoStatus(String codigo) => switch (codigo) {
      'disponivel' => const Color(0xFF1F9D55),
      'reuniao' => const Color(0xFFD4A106),
      'ligacao' => const Color(0xFF2563EB),
      'almoco' => const Color(0xFFE07B16),
      'nao_perturbe' => const Color(0xFF7C3AED),
      'ausente' => const Color(0xFFDC2626),
      'fora' => const Color(0xFF6B7280),
      _ => const Color(0xFF9CA3AF),
    };

class PontoStatus extends StatelessWidget {
  final String codigo;
  final double tam;
  const PontoStatus(this.codigo, {super.key, this.tam = 10});
  @override
  Widget build(BuildContext context) {
    final off = codigo == 'offline';
    final c = corDoStatus(codigo);
    return Container(
      width: tam,
      height: tam,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: off ? Colors.transparent : c,
        border: Border.all(color: off ? const Color(0xFF9CA3AF) : context.pal.card, width: off ? 2 : 1.5),
      ),
      child: codigo == 'nao_perturbe'
          ? Center(child: Container(width: tam * .5, height: 1.6, color: Colors.white))
          : null,
    );
  }
}
