import 'dart:io';

import 'package:nncloud_motor/motor.dart';
import 'package:test/test.dart';

void main() {
  late Directory raiz;
  setUp(() => raiz = Directory.systemTemp.createTempSync('nncloud_varredura_'));
  tearDown(() => raiz.deleteSync(recursive: true));

  test('lê arquivos e pastas', () {
    File('${raiz.path}/a.txt').writeAsStringSync('1');
    Directory('${raiz.path}/sub').createSync();
    File('${raiz.path}/sub/b.txt').writeAsStringSync('22');
    final r = Varredura(Ignorados()).varrer(raiz.path);
    expect(r.itens.keys, containsAll(['a.txt', 'sub', 'sub/b.txt']));
    expect(r.problemas, isEmpty);
  });

  // Só num sistema de arquivos que diferencia maiúsculas (Linux). No macOS e no
  // Windows os dois nomes são o MESMO arquivo, e o caso não existe.
  test('maiúsculas: o segundo nome vira problema (Linux)', () {
    File('${raiz.path}/Foto.jpg').writeAsStringSync('A');
    File('${raiz.path}/foto.jpg').writeAsStringSync('B');
    final distintos = raiz.listSync().length == 2;
    final r = Varredura(Ignorados()).varrer(raiz.path);
    if (!distintos) {
      expect(r.itens.length, 1);
      return;
    }
    expect(r.itens.keys, ['Foto.jpg']);
    expect(r.problemas.keys, ['foto.jpg']);
    expect(r.problemas['foto.jpg'], contains('maiúsculas'));
  });
}
