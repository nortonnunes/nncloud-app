// A borda clara das imagens do tema sazonal (areaUtilDaImagem).
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:nn_conversas/widgets/topo.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Uma imagem w×h vermelho-escura, com faixas brancas nas bordas pedidas.
Uint8List imagem(int w, int h,
    {int esq = 0, int dir = 0, int cima = 0, int baixo = 0, bool transparente = false}) {
  final px = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 4;
      final borda = x < esq || x >= w - dir || y < cima || y >= h - baixo;
      if (borda && transparente) {
        px.setAll(i, [0, 0, 0, 0]);
      } else if (borda) {
        px.setAll(i, [255, 255, 255, 255]);
      } else {
        px.setAll(i, [60, 2, 2, 255]);
      }
    }
  }
  return px;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('sem borda: a imagem inteira', () {
    expect(areaUtilDaImagem(imagem(400, 100), 400, 100), const Rect.fromLTWH(0, 0, 400, 100));
  });

  test('corta as faixas brancas de cada lado', () {
    expect(areaUtilDaImagem(imagem(400, 100, esq: 10, dir: 3, cima: 2, baixo: 4), 400, 100),
        const Rect.fromLTRB(10, 2, 397, 96));
  });

  test('borda transparente também sai', () {
    expect(areaUtilDaImagem(imagem(400, 100, esq: 6, transparente: true), 400, 100),
        const Rect.fromLTRB(6, 0, 400, 100));
  });

  test('faixa clara maior que 5% é conteúdo: não corta', () {
    expect(areaUtilDaImagem(imagem(400, 100, esq: 40), 400, 100), const Rect.fromLTWH(0, 0, 400, 100));
  });

  test('imagem toda branca: não corta nada', () {
    expect(areaUtilDaImagem(imagem(50, 50, esq: 50), 50, 50), const Rect.fromLTWH(0, 0, 50, 50));
  });

  test('pixels de menos (dado quebrado): a imagem inteira, sem erro', () {
    expect(areaUtilDaImagem(Uint8List(10), 400, 100), const Rect.fromLTWH(0, 0, 400, 100));
  });

  test('a imagem de verdade da Black Friday: tira as 10 colunas brancas da esquerda', () async {
    final codec = await ui.instantiateImageCodec(File('test/fixtures/fundo_black_friday.png').readAsBytesSync());
    final img = (await codec.getNextFrame()).image;
    final px = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final area = areaUtilDaImagem(px.buffer.asUint8List(), img.width, img.height);
    expect(area, Rect.fromLTRB(10, 0, img.width.toDouble(), img.height.toDouble()));
    img.dispose();
  });
}
