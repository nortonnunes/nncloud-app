// A barra do menu em ONDA, a mesma do NN Conecta (`body.menu-onda .topbar`):
// degradê da esquerda para a direita, ondas finas, grade de pontos e a borda de
// baixo curva — o caminho da máscara do site (`M0 0H100V100Q55 72 0 62Z`).
// As cores vêm do servidor (padrão, Configurações → CSS ou o tema sazonal).
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
    ..quadraticBezierTo(
        s.width * .55, base + curva * .72, 0, base + curva * .62)
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
    canvas.drawRect(r,
        Paint()..shader = LinearGradient(colors: [ini, fim]).createShader(r));

    // As ondas do site (`body.menu-onda .topbar::before`): as MESMAS curvas do SVG
    // de 400×120, esticadas na barra inteira. No escuro, duas e mais apagadas.
    final sx = s.width / 400, sy = s.height / 120;
    final linha = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.white.withValues(alpha: escuro ? .08 : .14);
    Path onda(List<double> v) => Path()
      ..moveTo(v[0] * sx, v[1] * sy)
      ..cubicTo(
          v[2] * sx, v[3] * sy, v[4] * sx, v[5] * sy, v[6] * sx, v[7] * sy)
      ..cubicTo(
          v[8] * sx, v[9] * sy, v[10] * sx, v[11] * sy, v[12] * sx, v[13] * sy);
    // "C a, b, c S d, e" → o primeiro controle do S é o reflexo de b em c.
    canvas.drawPath(
        onda([-20, 40, 80, 10, 160, 80, 260, 40, 360, 0, 440, 20, 460, 70]),
        linha);
    if (!escuro) {
      canvas.drawPath(
          onda([-20, 58, 80, 28, 160, 98, 260, 58, 360, 18, 440, 38, 460, 88]),
          linha);
    }
    canvas.drawPath(
        onda(
            [-40, 100, 60, 70, 150, 140, 250, 100, 350, 60, 430, 80, 470, 130]),
        linha);

    // A grade de pontos do canto direito (`::after` do site): 92×28, a 5% da
    // borda, na faixa curva — abaixo dos links.
    final ponto = Paint()..color = Colors.white.withValues(alpha: .5);
    final x0 = s.width * .95 - 92, y0 = s.height - 11 - 28;
    for (double y = y0 + 6.5; y < y0 + 28; y += 13) {
      for (double x = x0 + 6.5; x < x0 + 92; x += 13) {
        canvas.drawCircle(Offset(x, y), 1.5, ponto);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PintorOnda o) =>
      o.ini != ini || o.fim != fim || o.escuro != escuro || o.curva != curva;
}

/// A barra em onda com o conteúdo (os links do menu) por cima. As cores são as do
/// tema escolhido no NN Conecta (padrão, Configurações → CSS ou o tema sazonal).
/// A imagem do tema sazonal NÃO entra aqui: no site ela é o fundo da faixa de
/// cima (a da logo), e é lá que o app a põe.
class BarraOnda extends StatelessWidget {
  final Widget child;
  final double curva;
  const BarraOnda({super.key, required this.child, this.curva = 34});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final escuro = Theme.of(context).brightness == Brightness.dark;
    return CustomPaint(
      painter: _PintorOnda(p.topoIni, p.topoFim, escuro, curva),
      child: Padding(padding: EdgeInsets.only(bottom: curva), child: child),
    );
  }
}

/// Um link do menu na barra — o `.topnav-link` do site: só o texto, branco,
/// com fundo claro translúcido quando é a tela aberta.
class LinkMenu extends StatelessWidget {
  final String rotulo;
  final bool ativo;
  final int selo;
  final VoidCallback onTap;
  const LinkMenu(
      {super.key,
      required this.rotulo,
      required this.ativo,
      required this.onTap,
      this.selo = 0});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: Material(
        color: ativo ? Colors.white.withValues(alpha: .18) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          hoverColor: Colors.white.withValues(alpha: .12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(rotulo,
                  style: TextStyle(
                      color: ativo
                          ? Colors.white
                          : Colors.white.withValues(alpha: .88),
                      fontWeight: FontWeight.w600,
                      fontSize: 14.5)),
              if (selo > 0) ...[
                const SizedBox(width: 6),
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
      decoration: BoxDecoration(
          color: claro ? Colors.white : p.danger,
          borderRadius: BorderRadius.circular(99)),
      child: Text(n > 99 ? '99+' : '$n',
          style: TextStyle(
              color: claro ? p.danger : Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              height: 1)),
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
        border: Border.all(
            color: off ? const Color(0xFF9CA3AF) : context.pal.card,
            width: off ? 2 : 1.5),
      ),
      child: codigo == 'nao_perturbe'
          ? Center(
              child:
                  Container(width: tam * .5, height: 1.6, color: Colors.white))
          : null,
    );
  }
}
