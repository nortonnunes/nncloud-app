// A barra do menu em ONDA, a mesma do NN Conecta (`body.menu-onda .topbar`):
// degradê da esquerda para a direita, ondas finas, grade de pontos e a borda de
// baixo curva — o caminho da máscara do site (`M0 0H100V100Q55 72 0 62Z`).
// As cores vêm do servidor (padrão, Configurações → CSS ou o tema sazonal).
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

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

// ===================================================================
// A imagem do tema sazonal na faixa de cima
// ===================================================================

/// A área ÚTIL de uma imagem de topo: sem as faixas claras (quase brancas) ou
/// transparentes coladas nas bordas. É sobra de exportação — a imagem da Black
/// Friday veio com 10 colunas brancas à esquerda, a última já quase branca (226) —
/// e a faixa as mostraria como uma borda branca entre a janela e o tema.
/// "Clara" = os três canais a partir de 215, ou quase transparente.
///
/// [rgba]: os pixels (4 bytes cada). Só corta até [maxFracao] de cada lado; se a
/// faixa clara passa disso, a imagem é clara DE VERDADE e nada é cortado daquele lado.
Rect areaUtilDaImagem(Uint8List rgba, int w, int h, {double maxFracao = .05}) {
  final inteira = Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble());
  if (w <= 0 || h <= 0 || rgba.length < w * h * 4) return inteira;
  bool clara(int x, int y) {
    final i = (y * w + x) * 4;
    return rgba[i + 3] < 16 ||
        (rgba[i] >= 215 && rgba[i + 1] >= 215 && rgba[i + 2] >= 215);
  }

  // Amostra ~120 pontos por linha/coluna: basta para uma faixa contínua.
  final passoY = math.max(1, h ~/ 120), passoX = math.max(1, w ~/ 120);
  bool coluna(int x) {
    for (var y = 0; y < h; y += passoY) {
      if (!clara(x, y)) return false;
    }
    return true;
  }

  bool linha(int y) {
    for (var x = 0; x < w; x += passoX) {
      if (!clara(x, y)) return false;
    }
    return true;
  }

  int faixa(bool Function(int) clara, int de, int sentido, int max) {
    var n = 0;
    while (n < max && clara(de + n * sentido)) {
      n++;
    }
    return n >= max ? 0 : n;
  }

  final mx = (w * maxFracao).floor(), my = (h * maxFracao).floor();
  final esq = faixa(coluna, 0, 1, mx), dir = faixa(coluna, w - 1, -1, mx);
  final cima = faixa(linha, 0, 1, my), baixo = faixa(linha, h - 1, -1, my);
  if (esq + dir >= w || cima + baixo >= h) return inteira;
  return Rect.fromLTRB(esq.toDouble(), cima.toDouble(), (w - dir).toDouble(),
      (h - baixo).toDouble());
}

/// Pinta só a [area] da imagem, cobrindo a faixa inteira (o `cover` + centro do
/// `background` do site).
class PintorFundoTopo extends CustomPainter {
  final ui.Image imagem;
  final Rect area;
  const PintorFundoTopo(this.imagem, this.area);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || area.isEmpty) return;
    final ajuste = applyBoxFit(BoxFit.cover, area.size, size);
    final origem = Alignment.center.inscribe(ajuste.source, area);
    final destino = Alignment.center.inscribe(ajuste.destination, Offset.zero & size);
    canvas.drawImageRect(
        imagem,
        origem,
        destino,
        Paint()
          ..filterQuality = FilterQuality.medium
          ..isAntiAlias = true);
  }

  @override
  bool shouldRepaint(PintorFundoTopo antigo) =>
      antigo.imagem != imagem || antigo.area != area;
}
