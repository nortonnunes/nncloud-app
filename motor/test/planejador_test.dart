import 'package:nncloud_motor/motor.dart';
import 'package:test/test.dart';

// Montagem compacta das três visões.
ItemNuvem nf(int id, String nome, {int? pai, int versao = 1, int tam = 10, String? imp}) =>
    ItemNuvem(id: id, pai: pai, tipo: Tipo.arquivo, nome: nome, tamanho: tam, impressao: imp ?? 'i$id-v$versao', versao: versao);
ItemNuvem np(int id, String nome, {int? pai}) => ItemNuvem(id: id, pai: pai, tipo: Tipo.pasta, nome: nome);
ItemLocal lf(String c, {int tam = 10, int mt = 1000}) => ItemLocal(c, Tipo.arquivo, tam, mt);
ItemLocal lp(String c) => ItemLocal(c, Tipo.pasta, 0, 0);
ItemBase bf(String c, int id, {int versao = 1, int tam = 10, int mt = 1000, String? imp}) =>
    ItemBase(caminho: c, itemId: id, tipo: Tipo.arquivo, tamanho: tam, mtimeMs: mt, impressao: imp ?? 'i$id-v$versao', versao: versao);
ItemBase bp(String c, int id) => ItemBase(caminho: c, itemId: id, tipo: Tipo.pasta);

Map<String, ItemNuvem> nuvem(List<ItemNuvem> l) {
  final a = ArvoreNuvem();
  l.forEach(a.por);
  return a.porCaminho();
}

Future<Plano> plano(List<ItemNuvem> n, List<ItemLocal> l, List<ItemBase> b,
    {Map<String, String> imps = const {}, bool juncao = false, bool editar = true, bool Function(String)? soNuvem}) {
  return planejar(
    nuvem: nuvem(n),
    local: {for (final x in l) x.caminho: x},
    base: {for (final x in b) x.caminho: x},
    impressaoLocal: (c) async => imps[c],
    juncaoSegura: juncao,
    podeEditar: editar,
    soNuvem: soNuvem,
  );
}

List<String> txt(Plano p) => p.acoes.map((a) => a.toString()).toList();

void main() {
  group('arquivos', () {
    test('nada mudou: plano vazio', () async {
      expect((await plano([nf(1, 'a.txt')], [lf('a.txt')], [bf('a.txt', 1)])).vazio, isTrue);
    });
    test('só a data mudou no PC (conteúdo igual): só a base, sem reenviar', () async {
      final p = await plano([nf(1, 'a.txt')], [lf('a.txt', mt: 5000)], [bf('a.txt', 1)], imps: {'a.txt': 'i1-v1'});
      expect(txt(p), ['SoBase(a.txt)']);
      expect(p.de<SoBase>().single.base.mtimeMs, 5000);
    });
    test('só mudou no PC: envia com a versão de base', () async {
      final p = await plano([nf(1, 'a.txt')], [lf('a.txt', mt: 2000)], [bf('a.txt', 1)]);
      final e = p.de<EnviarAtualizacao>().single;
      expect([e.itemId, e.baseVersao], [1, 1]);
    });
    test('só mudou na nuvem: baixa, esperando o que estava na base', () async {
      final p = await plano([nf(1, 'a.txt', versao: 2)], [lf('a.txt')], [bf('a.txt', 1)]);
      expect(p.de<Baixar>().single.esperado?.itemId, 1);
    });
    test('mudou nos dois com conteúdo igual: só a base', () async {
      final p = await plano([nf(1, 'a.txt', versao: 2, tam: 20, imp: 'X')], [lf('a.txt', tam: 20, mt: 3)], [bf('a.txt', 1)], imps: {'a.txt': 'X'});
      expect(p.de<SoBase>().single.base.versao, 2);
      expect(p.acoes.length, 1);
    });
    test('mudou nos dois com conteúdo diferente: conflito', () async {
      final p = await plano([nf(1, 'a.txt', versao: 2, tam: 20, imp: 'X')], [lf('a.txt', tam: 20, mt: 3)], [bf('a.txt', 1)], imps: {'a.txt': 'Y'});
      expect(txt(p), ['Conflito(a.txt)']);
    });
    test('apagado no PC: lixeira da nuvem', () async {
      expect(txt(await plano([nf(1, 'a.txt')], [], [bf('a.txt', 1)])), ['LixeiraNuvem(a.txt)']);
    });
    test('apagado na nuvem: lixeira local', () async {
      expect(txt(await plano([], [lf('a.txt')], [bf('a.txt', 1)])), ['LixeiraLocal(a.txt)']);
    });
    test('mudou no PC e apagado na nuvem: a mudança vence (envia de novo)', () async {
      expect(txt(await plano([], [lf('a.txt', mt: 9)], [bf('a.txt', 1)])), ['EnviarNovo(a.txt)']);
    });
    test('mudou na nuvem e apagado no PC: a mudança vence (baixa)', () async {
      expect(txt(await plano([nf(1, 'a.txt', versao: 3)], [], [bf('a.txt', 1)])), ['Baixar(a.txt)']);
    });
    test('novo no PC: envia; novo na nuvem: baixa', () async {
      expect(txt(await plano([nf(2, 'n.txt')], [lf('l.txt')], [])), unorderedEquals(['EnviarNovo(l.txt)', 'Baixar(n.txt)']));
    });
    test('sumiu dos dois: só tira da base', () async {
      expect(txt(await plano([], [], [bf('a.txt', 1)])), ['RemoverBase(a.txt)']);
    });
    test('base vazia e arquivo igual nos dois lados: nada trafega', () async {
      final p = await plano([nf(1, 'a.txt', imp: 'X')], [lf('a.txt')], [], imps: {'a.txt': 'X'});
      expect(txt(p), ['SoBase(a.txt)']);
    });
    test('maiúsculas não importam na comparação', () async {
      expect((await plano([nf(1, 'Relatório.PDF')], [lf('relatório.pdf')], [bf('relatório.pdf', 1)])).acoes.whereType<Baixar>(), isEmpty);
    });
  });

  group('movidos e renomeados', () {
    test('renomeado na nuvem: renomeia no PC', () async {
      expect(txt(await plano([nf(1, 'novo.txt')], [lf('velho.txt')], [bf('velho.txt', 1)])), ['MoverLocal(velho.txt → novo.txt)']);
    });
    test('pasta movida na nuvem leva os filhos, sem baixar de novo', () async {
      final p = await plano([np(4, 'A'), np(5, 'B'), np(9, 'X', pai: 5), nf(1, 'a.txt', pai: 9)], [lp('A'), lp('A/X'), lf('A/X/a.txt'), lp('B')],
          [bp('A', 4), bp('A/X', 9), bf('A/X/a.txt', 1), bp('B', 5)]);
      expect(p.de<MoverLocal>().single.toString(), 'MoverLocal(A/X → B/X)');
      expect(p.de<Baixar>(), isEmpty);
      expect(p.de<LixeiraLocal>(), isEmpty);
    });
    test('renomeado no PC (mesmo conteúdo): renomeia na nuvem', () async {
      final p = await plano([nf(1, 'velho.txt', imp: 'X')], [lf('novo.txt')], [bf('velho.txt', 1, imp: 'X')], imps: {'novo.txt': 'X'});
      expect(txt(p), ['MoverNuvem(velho.txt → novo.txt)']);
    });
    test('só a caixa mudou no PC: renomeia na nuvem', () async {
      expect(txt(await plano([nf(1, 'relatorio.pdf')], [lf('Relatorio.pdf')], [bf('relatorio.pdf', 1)])), ['MoverNuvem(relatorio.pdf → Relatorio.pdf)']);
    });
    test('pasta renomeada no PC: uma operação na nuvem', () async {
      final p = await plano([np(4, 'Antigo'), nf(1, 'a.txt', pai: 4), nf(2, 'b.txt', pai: 4, tam: 5)],
          [lp('Novo'), lf('Novo/a.txt'), lf('Novo/b.txt', tam: 5)],
          [bp('Antigo', 4), bf('Antigo/a.txt', 1), bf('Antigo/b.txt', 2, tam: 5)]);
      expect(txt(p), ['MoverNuvem(Antigo → Novo)']);
    });
    test('conteúdo diferente não é movimento: lixeira + envio', () async {
      final p = await plano([nf(1, 'velho.txt', imp: 'X')], [lf('novo.txt')], [bf('velho.txt', 1, imp: 'X')], imps: {'novo.txt': 'Y'});
      expect(txt(p), unorderedEquals(['EnviarNovo(novo.txt)', 'LixeiraNuvem(velho.txt)']));
    });
  });

  group('pastas', () {
    test('pasta nova vazia nos dois sentidos', () async {
      expect(txt(await plano([np(3, 'Nuvem')], [lp('Local')], [])), unorderedEquals(['CriarPastaLocal(Nuvem)', 'CriarPastaNuvem(Local)']));
    });
    test('pasta apagada no PC vai inteira para a lixeira (uma operação)', () async {
      final p = await plano([np(4, 'P'), nf(1, 'a.txt', pai: 4), nf(2, 'b.txt', pai: 4)], [],
          [bp('P', 4), bf('P/a.txt', 1), bf('P/b.txt', 2)]);
      expect(p.exclusoesNuvem, 1);
      expect(p.de<LixeiraNuvem>().single.caminho, 'P');
    });
    test('pasta apagada no PC com arquivo alterado na nuvem: a pasta volta', () async {
      final p = await plano([np(4, 'P'), nf(1, 'a.txt', pai: 4, versao: 2), nf(2, 'b.txt', pai: 4)], [],
          [bp('P', 4), bf('P/a.txt', 1), bf('P/b.txt', 2)]);
      expect(p.de<LixeiraNuvem>().map((a) => a.caminho), ['P/b.txt']);
      expect(p.de<Baixar>().single.caminho, 'P/a.txt');
      expect(p.de<CriarPastaLocal>().single.caminho, 'P');
    });
    test('pasta apagada na nuvem com arquivo novo no PC: sobe de novo', () async {
      final p = await plano([], [lp('P'), lf('P/a.txt'), lf('P/novo.txt')], [bp('P', 4), bf('P/a.txt', 1)]);
      expect(txt(p), containsAll(['LixeiraLocal(P/a.txt)', 'EnviarNovo(P/novo.txt)', 'CriarPastaNuvem(P)']));
    });
    test('exclusões vêm do fundo para o raso, criações do raso para o fundo', () async {
      final p = await plano([np(1, 'A'), np(2, 'B', pai: 1)], [lp('X'), lp('X/Y')], []);
      final criar = p.acoes.whereType<CriarPastaNuvem>().map((a) => a.caminho).toList();
      expect(criar, ['X', 'X/Y']);
    });
  });

  group('proteções', () {
    test('junção segura: nada é apagado em lado nenhum', () async {
      final p = await plano([nf(1, 'so-nuvem.txt')], [lf('so-pc.txt')], [bf('so-nuvem.txt', 1), bf('so-pc.txt', 2)], juncao: true);
      expect(p.exclusoesLocais + p.exclusoesNuvem, 0);
      expect(txt(p), unorderedEquals(['Baixar(so-nuvem.txt)', 'EnviarNovo(so-pc.txt)']));
    });
    test('só leitura: alteração local vira problema, exclusão local é restaurada', () async {
      final p = await plano([nf(1, 'a.txt'), nf(2, 'b.txt')], [lf('a.txt', mt: 9), lf('novo.txt')], [bf('a.txt', 1), bf('b.txt', 2)], editar: false);
      expect(p.exclusoesNuvem, 0);
      expect(p.de<Problema>().length, 2);
      expect(p.de<Baixar>().single.caminho, 'b.txt');
    });
    test('nome que o Windows não aceita vira problema, nunca vai para a nuvem', () async {
      final p = await plano([], [lf('relatório:final.txt'), lf('com1.txt'), lf('fim. ')], []);
      expect(p.de<Problema>().length, 3);
      expect(p.de<EnviarNovo>(), isEmpty);
    });
    test('pasta e arquivo com o mesmo nome: problema, nada é apagado', () async {
      final p = await plano([np(1, 'X')], [lf('X')], []);
      expect(txt(p), ['Problema(X: existe uma pasta e um arquivo com este nome)']);
    });
  });

  group('só na nuvem (pasta de envio e sincronização seletiva)', () {
    bool tudo(String _) => true;
    bool arquivo(String c) => c == 'Arquivo' || c.startsWith('Arquivo/');

    test('fora do computador: não desce', () async {
      expect((await plano([nf(1, 'a.txt')], [], [], soNuvem: tudo)).vazio, isTrue);
    });
    test('fora do computador e com base (já liberado): só tira a base, NUNCA apaga na nuvem', () async {
      expect(txt(await plano([nf(1, 'a.txt')], [], [bf('a.txt', 1)], soNuvem: tudo)), ['RemoverBase(a.txt)']);
    });
    test('mudou na nuvem, fora do computador: continua só na nuvem', () async {
      expect(txt(await plano([nf(1, 'a.txt', versao: 3)], [], [bf('a.txt', 1)], soNuvem: tudo)), ['RemoverBase(a.txt)']);
    });
    test('arquivo novo no computador: sobe normalmente', () async {
      expect(txt(await plano([], [lf('novo.pdf')], [], soNuvem: tudo)), ['EnviarNovo(novo.pdf)']);
    });
    test('mesmo nome, conteúdo diferente: a versão do PC sobe como conflito e a da nuvem NÃO desce', () async {
      final p = await plano([nf(1, 'a.txt', tam: 20, imp: 'X')], [lf('a.txt', tam: 20)], [], imps: {'a.txt': 'Y'}, soNuvem: tudo);
      expect(p.de<Conflito>().single.baixar, isFalse);
    });
    test('fora da área só na nuvem: regras de sempre (baixa e apaga)', () async {
      expect(txt(await plano([nf(1, 'b.txt')], [], [], soNuvem: arquivo)), ['Baixar(b.txt)']);
      expect(txt(await plano([nf(1, 'b.txt')], [], [bf('b.txt', 1)], soNuvem: arquivo)), ['LixeiraNuvem(b.txt)']);
    });
    test('pasta seletiva: nem a pasta nem o conteúdo descem', () async {
      final p = await plano([np(1, 'Arquivo'), nf(2, 'x.pdf', pai: 1), np(3, 'Sub', pai: 1), nf(4, 'y.pdf', pai: 3)], [], [], soNuvem: arquivo);
      expect(p.vazio, isTrue);
    });
    test('pasta normal apagada no PC com pasta só na nuvem dentro: NÃO vai para a lixeira, é recriada', () async {
      bool sel(String c) => c == 'Proj/Antigo' || c.startsWith('Proj/Antigo/');
      final p = await plano([np(1, 'Proj'), np(2, 'Antigo', pai: 1), nf(3, 'velho.pdf', pai: 2)], [], [bp('Proj', 1)], soNuvem: sel);
      expect(p.de<LixeiraNuvem>(), isEmpty);
      expect(txt(p), contains('CriarPastaLocal(Proj)'));
    });
    test('pasta de envio apagada no PC: a nuvem fica', () async {
      final p = await plano([np(1, 'Notas'), nf(2, 'n.pdf', pai: 1)], [], [bp('Notas', 1), bf('Notas/n.pdf', 2)], soNuvem: tudo);
      expect(p.de<LixeiraNuvem>(), isEmpty);
      expect(p.exclusoesLocais, 0);
    });
  });
}
