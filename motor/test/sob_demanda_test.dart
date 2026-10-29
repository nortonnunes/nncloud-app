// O "NN Cloud" sob demanda do Windows (ProvedorSobDemanda) contra a API de teste de
// verdade, com o sistema de arquivos SIMULADO: o NativoFalso guarda o estado de
// placeholder (identidade, em dia, hidratado) ao lado de arquivos comuns.
//
//   NCL_E2E=1 NCL_API=http://127.0.0.1:8782 NCL_PREPARAR="php …/prep_fp.php" dart test test/sob_demanda_test.dart
//
// Sem NCL_E2E o teste é pulado (precisa da API e do S3 de teste no ar).
import 'dart:convert';
import 'dart:io';

import 'package:nncloud_motor/motor.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

final _ligado = Platform.environment['NCL_E2E'] == '1';

class Ph {
  String identidade;
  bool emDia;
  bool hidratado;
  Ph(this.identidade, {this.hidratado = false}) : emDia = true;
}

/// O Windows de mentira: placeholder = arquivo/pasta comum + estado neste mapa.
class NativoFalso implements NativoNuvem {
  final Map<String, Ph> ph = {};
  String _k(String c) => p.normalize(c);

  @override
  Future<void> criarPlaceholders(String pasta, List<NovoPlaceholder> itens) async {
    for (final i in itens) {
      final c = _k(p.join(pasta, i.nome));
      if (FileSystemEntity.typeSync(c) != FileSystemEntityType.notFound) continue;
      if (i.pasta) {
        Directory(c).createSync(recursive: true);
        ph[c] = Ph(i.identidade, hidratado: true);
      } else {
        File(c).writeAsBytesSync(const []);
        ph[c] = Ph(i.identidade);
      }
    }
  }

  @override
  Future<EstadoLocal?> estado(String caminho) async {
    final c = _k(caminho);
    final t = FileSystemEntity.typeSync(c, followLinks: false);
    if (t == FileSystemEntityType.notFound) return null;
    final e = ph[c];
    final pasta = t == FileSystemEntityType.directory;
    if (e == null) return EstadoLocal(pasta: pasta);
    return EstadoLocal(placeholder: true, emDia: e.emDia, pasta: pasta, hidratado: e.hidratado, identidade: e.identidade);
  }

  @override
  Future<bool> atualizar(String caminho, String identidade, {int? tamanho, int? criadoMs, int? modificadoMs, bool desidratar = false}) async {
    final e = ph[_k(caminho)];
    if (e == null) return false;
    e
      ..identidade = identidade
      ..emDia = true;
    if (desidratar && File(_k(caminho)).existsSync()) {
      File(_k(caminho)).writeAsBytesSync(const []);
      e.hidratado = false;
    }
    return true;
  }

  @override
  Future<bool> converter(String caminho, String identidade, {bool desidratar = false}) async {
    final c = _k(caminho);
    final dir = FileSystemEntity.isDirectorySync(c);
    ph[c] = Ph(identidade, hidratado: dir || !desidratar);
    if (desidratar && !dir) File(c).writeAsBytesSync(const []);
    return true;
  }

  @override
  Future<bool> desidratar(String caminho) async {
    final e = ph[_k(caminho)];
    if (e == null) return false;
    File(_k(caminho)).writeAsBytesSync(const []);
    e.hidratado = false;
    return true;
  }

  @override
  Future<void> mover(String de, String para) async {
    final a = _k(de), b = _k(para);
    if (FileSystemEntity.isDirectorySync(a)) {
      Directory(a).renameSync(b);
    } else {
      File(a).renameSync(b);
    }
    final mover = <String, Ph>{};
    ph.removeWhere((k, v) {
      if (k == a || p.isWithin(a, k)) {
        mover[b + k.substring(a.length)] = v;
        return true;
      }
      return false;
    });
    ph.addAll(mover);
  }

  @override
  Future<void> apagar(String caminho) async {
    final c = _k(caminho);
    if (FileSystemEntity.isDirectorySync(c)) {
      Directory(c).deleteSync();
    } else {
      File(c).deleteSync();
    }
    ph.remove(c);
  }

  // ---- o que o usuário faz no Explorer ----

  /// Abrir: o Windows pede o conteúdo ao app e o grava no placeholder.
  Future<void> abrir(ProvedorSobDemanda pr, String caminho) async {
    final c = _k(caminho);
    final e = ph[c]!;
    final tmp = File('$c.baixando');
    await pr.baixar(e.identidade, tmp);
    File(c).writeAsBytesSync(tmp.readAsBytesSync());
    tmp.deleteSync();
    e.hidratado = true;
  }

  /// Editar um arquivo: o Windows tira o placeholder de "em dia".
  void editar(String caminho, List<int> bytes) {
    final c = _k(caminho);
    File(c).writeAsBytesSync(bytes);
    File(c).setLastModifiedSync(DateTime.now().subtract(const Duration(seconds: 10)));
    final e = ph[c];
    if (e != null) {
      e
        ..emDia = false
        ..hidratado = true;
    }
  }
}

void main() {
  if (!_ligado) {
    test('sob demanda (Windows)', () {}, skip: 'precisa da API e do S3 de teste no ar: defina NCL_E2E=1');
    return;
  }
  final apiBase = Platform.environment['NCL_API'] ?? 'http://127.0.0.1:8782';
  late Map<String, dynamic> j;
  late Directory base;
  late NativoFalso n;
  late ProvedorSobDemanda pr;
  late Api ana2;
  final eventos = <EventoSobDemanda>[];

  String c(String rel) => p.join(base.path, 'NN Cloud', rel.split('/').join(p.separator));
  Future<Map<String, dynamic>> item(Api a, int id) => a.fpItem('i$id');

  /// O outro computador da Ana manda uma versão nova (na nuvem).
  Future<EnvioConcluido> versaoNaNuvem(int id, String texto) async {
    final it = await item(ana2, id);
    final f = File(p.join(base.path, 'tmp-${DateTime.now().microsecondsSinceEpoch}'))..writeAsStringSync(texto);
    final imp = (await Impressao.deArquivo(f))!;
    return (await enviarConteudo(ana2, f, imp, f.statSync(), {'nome': it['nome'], 'item_id': id, 'base_versao': it['versao']}))!;
  }

  setUpAll(() async {
    final prep = Platform.environment['NCL_PREPARAR']!.split(' ');
    final r = await Process.run(prep.first, prep.sublist(1), workingDirectory: '../..');
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    j = jsonDecode((r.stdout as String).trim().split('\n').last) as Map<String, dynamic>;
    base = Directory.systemTemp.createTempSync('ncl-fp-');
    Directory(p.join(base.path, 'NN Cloud')).createSync();
    n = NativoFalso();
    ana2 = Api(apiBase, token: j['ana2'] as String);
    pr = ProvedorSobDemanda(
      api: Api(apiBase, token: j['ana'] as String),
      nativo: n,
      raiz: p.join(base.path, 'NN Cloud'),
      arquivoEstado: File(p.join(base.path, 'estado.json')),
      computador: 'DESKTOP-ANA',
      esperaGravacao: Duration.zero,
      aoEvento: eventos.add,
    );
  });

  tearDownAll(() => base.deleteSync(recursive: true));

  test('primeira vez: a árvore inteira vira placeholders (sem baixar nada)', () async {
    await pr.sincronizar();
    for (final rel in ['Meu Drive', 'Compartilhados comigo', 'Drives compartilhados', 'Meu Drive/Projetos', 'Drives compartilhados/Jurídico']) {
      expect(Directory(c(rel)).existsSync(), isTrue, reason: rel);
    }
    for (final rel in ['Meu Drive/notas.txt', 'Meu Drive/Projetos/plano.txt', 'Drives compartilhados/Jurídico/contrato.pdf',
      'Compartilhados comigo/Relatórios/q1.xlsx']) {
      final e = (await n.estado(c(rel)))!;
      expect(e.placeholder && e.emDia && !e.hidratado, isTrue, reason: rel);
    }
    expect(File(c('Meu Drive/notas.txt')).lengthSync(), 0);   // nada desceu
    expect(pr.ancora, isNotNull);
    expect(pr.indice['i${j['plano']}'], 'Meu Drive/Projetos/plano.txt');
  });

  test('abrir baixa o conteúdo conferido', () async {
    await n.abrir(pr, c('Meu Drive/Projetos/plano.txt'));
    expect(File(c('Meu Drive/Projetos/plano.txt')).readAsStringSync(), 'plano v1');
  });

  test('arquivo e pasta novos no disco sobem e viram placeholders', () async {
    File(c('Meu Drive/novo.txt')).writeAsStringSync('feito no Explorer');
    Directory(c('Meu Drive/Pasta nova/sub')).createSync(recursive: true);
    File(c('Meu Drive/Pasta nova/sub/dentro.txt')).writeAsStringSync('dentro');
    File(c('Meu Drive/Pasta nova/desktop.ini')).writeAsStringSync('ignorado');
    pr.localMudou([c('Meu Drive/novo.txt'), c('Meu Drive/Pasta nova/sub/dentro.txt'), c('Meu Drive/Pasta nova')]);
    await pr.processarLocais();
    final e = (await n.estado(c('Meu Drive/novo.txt')))!;
    expect(e.placeholder && e.emDia, isTrue);
    final novo = await item(ana2, numeroDoItem(idDaIdentidade(e.identidade))!);
    expect(novo['nome'], 'novo.txt');
    expect(novo['pai'], 'meu');
    final pasta = (await n.estado(c('Meu Drive/Pasta nova/sub')))!;
    expect(pasta.placeholder, isTrue);
    final filhos = await ana2.fpFilhos(idDaIdentidade(pasta.identidade), 0);
    expect((filhos['itens'] as List).map((i) => i['nome']), ['dentro.txt']);
    expect((await n.estado(c('Meu Drive/Pasta nova/desktop.ini')))!.placeholder, isFalse);
  });

  test('editar um arquivo aberto sobe uma versão nova', () async {
    n.editar(c('Meu Drive/Projetos/plano.txt'), utf8.encode('plano v2'));
    pr.localMudou([c('Meu Drive/Projetos/plano.txt')]);
    await pr.processarLocais();
    final e = (await n.estado(c('Meu Drive/Projetos/plano.txt')))!;
    expect(e.emDia, isTrue);
    final it = await item(ana2, j['plano'] as int);
    expect(it['versao'], versaoDaIdentidade(e.identidade));
    expect(it['tamanho'], 8);
  });

  test('mudanças da nuvem chegam: versão nova, renomeado, arquivo novo, apagado', () async {
    await versaoNaNuvem(j['notas'] as int, 'notas da nuvem');
    await ana2.renomear(j['contrato'] as int, 'contrato-assinado.pdf');
    final f = File(p.join(base.path, 'n.txt'))..writeAsStringSync('nasceu na nuvem');
    await enviarConteudo(ana2, f, (await Impressao.deArquivo(f))!, f.statSync(), {'nome': 'da-nuvem.txt', 'pasta_id': j['proj']});
    final novoE = (await n.estado(c('Meu Drive/novo.txt')))!;
    await ana2.lixeira([numeroDoItem(idDaIdentidade(novoE.identidade))!], confirmado: true);
    await pr.sincronizar();
    final notas = (await n.estado(c('Meu Drive/notas.txt')))!;
    expect(versaoDaIdentidade(notas.identidade), (await item(ana2, j['notas'] as int))['versao']);
    expect(File(c('Drives compartilhados/Jurídico/contrato-assinado.pdf')).existsSync(), isTrue);
    expect(File(c('Drives compartilhados/Jurídico/contrato.pdf')).existsSync(), isFalse);
    expect((await n.estado(c('Meu Drive/Projetos/da-nuvem.txt')))?.placeholder, isTrue);
    expect(File(c('Meu Drive/novo.txt')).existsSync(), isFalse);
    await n.abrir(pr, c('Meu Drive/notas.txt'));
    expect(File(c('Meu Drive/notas.txt')).readAsStringSync(), 'notas da nuvem');
  });

  test('versão nova na nuvem tira do disco o conteúdo antigo', () async {
    await versaoNaNuvem(j['notas'] as int, 'notas v3');
    await pr.sincronizar();
    final e = (await n.estado(c('Meu Drive/notas.txt')))!;
    expect(e.hidratado, isFalse);
    await n.abrir(pr, c('Meu Drive/notas.txt'));
    expect(File(c('Meu Drive/notas.txt')).readAsStringSync(), 'notas v3');
  });

  test('editado aqui e na nuvem: a versão daqui vira cópia de conflito', () async {
    await versaoNaNuvem(j['plano'] as int, 'plano da nuvem');
    n.editar(c('Meu Drive/Projetos/plano.txt'), utf8.encode('plano daqui'));
    pr.localMudou([c('Meu Drive/Projetos/plano.txt')]);
    await pr.processarLocais();
    final copias = Directory(c('Meu Drive/Projetos')).listSync().map((e) => p.basename(e.path)).where((x) => x.contains('conflito')).toList();
    expect(copias, hasLength(1));
    expect(File(c('Meu Drive/Projetos/${copias.first}')).readAsStringSync(), 'plano daqui');
    final orig = (await n.estado(c('Meu Drive/Projetos/plano.txt')))!;
    expect(orig.placeholder && orig.emDia && !orig.hidratado, isTrue);
    await n.abrir(pr, c('Meu Drive/Projetos/plano.txt'));
    expect(File(c('Meu Drive/Projetos/plano.txt')).readAsStringSync(), 'plano da nuvem');
    expect(eventos.where((e) => e.tipo == 'conflito'), isNotEmpty);
  });

  test('renomear e mover pelo Explorer vão para a nuvem; apagar vai para a lixeira', () async {
    final notas = (await n.estado(c('Meu Drive/notas.txt')))!;
    expect(await pr.aoRenomear(notas.identidade!, c('Meu Drive/notas.txt'), c('Meu Drive/Projetos/notas-2026.txt')), isTrue);
    await n.mover(c('Meu Drive/notas.txt'), c('Meu Drive/Projetos/notas-2026.txt'));   // o Windows completa
    final it = await item(ana2, j['notas'] as int);
    expect(it['nome'], 'notas-2026.txt');
    expect(it['pai'], 'i${j['proj']}');
    // Para a Lixeira do Windows (fora da pasta) = apagar.
    expect(await pr.aoRenomear(notas.identidade!, c('Meu Drive/Projetos/notas-2026.txt'), p.join(base.path, 'Lixeira', 'x')), isTrue);
    await expectLater(ana2.fpItem('i${j['notas']}'), throwsA(isA<ApiErro>()));
    // As pastas fixas não se apagam nem se renomeiam.
    expect(await pr.aoApagar('meu', c('Meu Drive')), isFalse);
    expect(await pr.aoRenomear('drives', c('Drives compartilhados'), c('Drives')), isFalse);
    // Na sincronização seguinte nada volta nem some por engano.
    await pr.sincronizar();
    expect(File(c('Meu Drive/Projetos/notas-2026.txt')).existsSync(), isTrue);   // o Windows apagaria; aqui ele ficou
  });

  test('pasta só de leitura: o Explorer não consegue apagar, e arquivo novo vira problema', () async {
    final q1 = (await n.estado(c('Compartilhados comigo/Relatórios/q1.xlsx')))!;
    expect(await pr.aoApagar(q1.identidade!, c('Compartilhados comigo/Relatórios/q1.xlsx')), isFalse);
    File(c('Compartilhados comigo/Relatórios/meu.txt')).writeAsStringSync('x');
    eventos.clear();
    pr.localMudou([c('Compartilhados comigo/Relatórios/meu.txt')]);
    await pr.processarLocais();
    expect(eventos.where((e) => e.tipo == 'problema' && e.caminho.endsWith('meu.txt')), isNotEmpty);
    expect((await n.estado(c('Compartilhados comigo/Relatórios/meu.txt')))!.placeholder, isFalse);
    // Arquivo solto na raiz ou em "Drives compartilhados" também não sobe.
    File(c('solto.txt')).writeAsStringSync('x');
    pr.localMudou([c('solto.txt')]);
    await pr.processarLocais();
    expect(eventos.where((e) => e.tipo == 'problema' && e.caminho == 'solto.txt'), isNotEmpty);
  });

  test('liberar depois de enviar: o arquivo sobe e sai do disco', () async {
    pr.liberarAposEnviar = true;
    File(c('Meu Drive/vai-pra-nuvem.bin')).writeAsBytesSync(List.generate(9 * 1024 * 1024 + 5, (i) => i % 251));
    pr.localMudou([c('Meu Drive/vai-pra-nuvem.bin')]);
    await pr.processarLocais();
    final e = (await n.estado(c('Meu Drive/vai-pra-nuvem.bin')))!;
    expect(e.placeholder && e.emDia && !e.hidratado, isTrue);
    expect(File(c('Meu Drive/vai-pra-nuvem.bin')).lengthSync(), 0);
    final it = await item(ana2, numeroDoItem(idDaIdentidade(e.identidade))!);
    expect(it['tamanho'], 9 * 1024 * 1024 + 5);
    pr.liberarAposEnviar = false;
  });

  test('app reaberto: âncora guardada continua; editado com o app fechado sobe na volta completa', () async {
    pr.encerrar();
    final pr2 = ProvedorSobDemanda(
      api: Api(apiBase, token: j['ana'] as String),
      nativo: n,
      raiz: pr.raiz,
      arquivoEstado: pr.arquivoEstado,
      computador: 'DESKTOP-ANA',
      esperaGravacao: Duration.zero,
    )..carregar();
    expect(pr2.ancora, pr.ancora);
    expect(pr2.indice['i${j['proj']}'], 'Meu Drive/Projetos');
    await n.abrir(pr2, c('Meu Drive/Projetos/da-nuvem.txt'));
    n.editar(c('Meu Drive/Projetos/da-nuvem.txt'), utf8.encode('editado offline'));
    await pr2.sincronizar(completo: true);
    final e = (await n.estado(c('Meu Drive/Projetos/da-nuvem.txt')))!;
    expect(e.emDia, isTrue);
    expect((await item(ana2, numeroDoItem(idDaIdentidade(e.identidade))!))['tamanho'], 'editado offline'.length);
  });

  test('âncora desconhecida: volta à árvore inteira sem perder nada', () async {
    pr.ancora = 'x' * 32;
    await pr.sincronizar();
    expect(pr.ancora, isNot('x' * 32));
    expect((await n.estado(c('Meu Drive/Projetos/da-nuvem.txt')))?.placeholder, isTrue);
  });
}
