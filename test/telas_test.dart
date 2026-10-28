// Renderiza as telas com fontes de verdade (Roboto e os ícones do Material)
// para conferir o desenho: `flutter test test/telas_test.dart --update-goldens`
// gera os PNG em test/goldens/. Sem `--update-goldens` confere contra eles.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nncloud/servicos/armazenamento.dart';
import 'package:nncloud/servicos/controle.dart';
import 'package:nncloud/servicos/notificacoes.dart';
import 'package:nncloud/telas/casca.dart';
import 'package:nncloud/telas/conectar.dart';
import 'package:nncloud/tema.dart';
import 'package:nncloud_motor/motor.dart';
import 'package:path/path.dart' as p;

Future<void> fontes() async {
  final raiz = p.dirname(p.dirname(File(Platform.resolvedExecutable).resolveSymbolicLinksSync()));
  // resolvedExecutable = …/flutter/bin/cache/dart-sdk/bin/dart
  final mat = Directory(p.join(p.dirname(p.dirname(raiz)), 'artifacts', 'material_fonts'));
  Future<void> carregar(String familia, List<String> arquivos) async {
    final l = FontLoader(familia);
    for (final a in arquivos) {
      final f = File(p.join(mat.path, a));
      if (f.existsSync()) l.addFont(Future.value(ByteData.view(f.readAsBytesSync().buffer)));
    }
    await l.load();
  }

  await carregar('Roboto', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']);
  await carregar('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

Controle controleFalso(Armazenamento arm) {
  final c = Controle(arm, Notificacoes())
    ..situacao = Situacao.ok
    ..ultimoSync = DateTime(2026, 10, 28, 14, 30)
    ..eu = {
      'pessoa': {'nome': 'Ana Lima', 'email': 'ana@nortonnunes.com.br'},
      'meu_drive': {'id': 1, 'usado': 1288490188, 'limite': 5368709120},
      'config': {'intervalo_seg': 30, 'web': 'https://nnconecta.com/cloud'},
      'app': {'macos': null, 'windows': null},
    }
    ..pares = [
      {'id': 1, 'nome': 'Contratos', 'caminho_local': '/Users/ana/Documents/Contratos', 'raiz_nome': 'Contratos', 'arquivos': 1284,
        'ultimo_sync_em': '2026-10-28 14:30:00'},
      {'id': 2, 'nome': 'Financeiro', 'caminho_local': '/Users/ana/Financeiro', 'raiz_nome': 'Financeiro — Contas', 'arquivos': 312,
        'ultimo_sync_em': '2026-10-28 14:12:00'},
    ];
  final r1 = ResultadoPar(1);
  final r2 = ResultadoPar(2)
    ..problemas.add('relatório:final.xlsx: não pode ir para a nuvem: o nome não pode ter / \\ : * ? " < > | (tem ":")');
  c.resultados = {1: r1, 2: r2};
  c.aguardando.add(ExclusaoEmMassa(2, 64, 0, 64, ['2025/janeiro.pdf', '2025/fevereiro.pdf', '2025/março.pdf']));
  for (final (t, cam) in [('enviado', 'Contratos/2026/proposta.pdf'), ('baixado', 'Financeiro/fluxo de caixa.xlsx'), ('conflito', 'Relatório (conflito de NOTEBOOK-ANA 2026-10-28 14h30).docx')]) {
    c.atividade.add(LinhaAtividade(t, cam, par: 1, quando: DateTime(2026, 10, 28, 14, 30)));
  }
  return c;
}

Widget app(Widget home, {bool escuro = false}) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: Tema.claro(),
      darkTheme: Tema.escuro(),
      themeMode: escuro ? ThemeMode.dark : ThemeMode.light,
      home: home,
    );

void main() {
  late Armazenamento arm;
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await fontes();
    arm = Armazenamento();
    await arm.iniciar(base: Directory.systemTemp.createTempSync('ncl-telas-'));
  });

  Future<void> tela(WidgetTester t, String nome, Widget w, {bool escuro = false, Size tamanho = const Size(1000, 700)}) async {
    t.view.physicalSize = tamanho;
    t.view.devicePixelRatio = 1;
    await t.pumpWidget(app(w, escuro: escuro));
    await t.pump(const Duration(milliseconds: 100));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$nome.png'));
  }

  testWidgets('conectar', (t) async {
    final c = Controle(arm, Notificacoes());
    await tela(t, 'conectar', TelaConectar(c));
    c.codigo = 'BKTR-NWQZ';
    c.urlConectar = 'https://nnconecta.com/cloud/conectar';
    await tela(t, 'conectar_codigo', TelaConectar(c));
  });

  for (final escuro in [false, true]) {
    for (final (i, nome) in [(0, 'visao_geral'), (1, 'pastas'), (3, 'problemas'), (4, 'configuracoes')]) {
      testWidgets('$nome${escuro ? ' escuro' : ''}', (t) async {
        final c = controleFalso(arm);
        await tela(t, '$nome${escuro ? '_escuro' : ''}', Casca(c, ValueNotifier(ThemeMode.light), ValueNotifier(i)),
            escuro: escuro, tamanho: i == 0 ? const Size(1000, 900) : const Size(1000, 700));
      });
    }
  }
}
