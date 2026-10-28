// O contrato com o servidor PHP: os valores esperados foram GERADOS pelo
// próprio `Nome`/`Impressao` do NN Conecta (com o Normalizer do intl) e
// gravados em `fixtures/contrato_php.json`. O Dart tem de reproduzi-los.
import 'dart:convert';
import 'dart:io';

import 'package:nncloud_motor/motor.dart';
import 'package:test/test.dart';

void main() {
  final c = jsonDecode(File('test/fixtures/contrato_php.json').readAsStringSync()) as Map<String, dynamic>;

  test('NFC, validade, extensão e chave iguais ao PHP', () {
    for (final n in (c['nomes'] as List).cast<Map<String, dynamic>>()) {
      final nome = n['nome'] as String;
      expect(nfc(nome), n['nfc'], reason: 'nfc de ${jsonEncode(nome)}');
      expect(nomeValido(nome), n['valido'], reason: 'validade de ${jsonEncode(nome)} (${motivoNome(nome)})');
      expect(extensao(nome), n['ext'], reason: 'extensão de ${jsonEncode(nome)}');
      if (n['chave'] != null) expect(chaveNome(nome), n['chave'], reason: 'chave de ${jsonEncode(nome)}');
    }
  });

  test('nome da cópia de conflito igual ao PHP', () {
    for (final x in (c['conflitos'] as List).cast<Map<String, dynamic>>()) {
      expect(nomeConflito(x['nome'] as String, x['pc'] as String, DateTime(2026, 10, 28, 14, 30)), x['resultado'], reason: x['nome'] as String);
    }
  });

  test('impressão igual ao PHP (0 B, 1 B, 8 MiB ± 1, 2 partes e meia)', () async {
    for (final x in (c['impressoes'] as List).cast<Map<String, dynamic>>()) {
      final t = x['tamanho'] as int;
      final dados = List<int>.generate(t, (i) => (i * 7) % 251);
      final m = Impressao.deBytes(dados);
      expect(m.partes, x['partes'], reason: 'partes de $t bytes');
      expect(m.hex, x['hex'], reason: 'impressão de $t bytes');
      final tmp = File('${Directory.systemTemp.path}/ncl-imp-$t.bin')..writeAsBytesSync(dados);
      final a = await Impressao.deArquivo(tmp);
      expect(a!.hex, x['hex'], reason: 'impressão lida do disco, $t bytes');
      tmp.deleteSync();
    }
  });

  test('ignorados', () {
    final ig = Ignorados();
    for (final n in ['.DS_Store', 'thumbs.db', '~\$Relatório.docx', '.~lock.planilha.ods#', 'x.tmp', 'baixando.crdownload', '._foto.jpg', '.nncloud-tmp-1']) {
      expect(ig.nome(n), isTrue, reason: n);
    }
    for (final n in ['relatório.docx', 'tmp.txt', 'part.txt', 'lock.ods']) {
      expect(ig.nome(n), isFalse, reason: n);
    }
    expect(ig.caminho('Projetos/.DS_Store'), isTrue);
  });
}
