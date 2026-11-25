// O "NN Cloud" no Explorer (ProvedorSobDemanda) quando UM item dá problema: a volta
// tem de seguir. Caso real (nov/2026): um arquivo do Meu Drive que não dava para
// atualizar no disco (aberto no Excel) abortava a volta inteira — "Compartilhados
// comigo" e "Drives compartilhados" ficavam vazios para sempre, porque a volta
// recomeçava a cada ciclo e parava no mesmo lugar.
//
// Sem rede: a API e o Windows são falsos, em memória.
//   dart test test/sob_demanda_falhas_test.dart
import 'dart:io';

import 'package:nncloud_motor/motor.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A nuvem de mentira: a árvore do domínio (id → filhos) e as mudanças a entregar.
class ApiFalsa implements Api {
  final Map<String, List<Map<String, dynamic>>> nuvem = {};
  final Map<String, int> chamadasFilhos = {};
  int ancoras = 0;
  int chamadasMudancas = 0;
  List<Map<String, dynamic>> proximasMudancas = [];
  Object? erroFilhos; // lançado ao pedir os filhos de [idErro]
  String idErro = '';

  static Map<String, dynamic> item(String id, String pai, String nome, {bool pasta = false, int versao = 1}) => {
        'id': id, 'pai': pai, 'nome': nome, 'tipo': pasta ? 'pasta' : 'arquivo',
        'tamanho': pasta ? null : 10, 'versao': versao, 'criado_ms': 1, 'modificado_ms': 1,
      };

  @override
  Future<String> fpAncora() async => 'ancora${++ancoras}';

  @override
  Future<Map<String, dynamic>> fpFilhos(String id, int depoisDe) async {
    chamadasFilhos[id] = (chamadasFilhos[id] ?? 0) + 1;
    if (id == idErro && erroFilhos != null) throw erroFilhos!;
    return {'itens': nuvem[id] ?? [], 'proximo': null};
  }

  @override
  Future<Map<String, dynamic>> fpMudancas(String ancora) async {
    chamadasMudancas++;
    final itens = proximasMudancas;
    proximasMudancas = [];
    return {'estado': 'ok', 'itens': itens, 'removidos': [], 'ancora': 'ancora${++ancoras}', 'mais': false};
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('ApiFalsa: ${i.memberName}');
}

class Ph {
  String identidade;
  bool emDia = true;
  Ph(this.identidade);
}

/// O Windows de mentira. [emUso]: caminhos cujo placeholder não deixa ser atualizado
/// (o CfUpdatePlaceholder falha com o arquivo aberto); [nomesRecusados]: nomes que
/// o lote de criação recusa.
class NativoFalso implements NativoNuvem {
  final Map<String, Ph> ph = {};
  final Set<String> emUso = {};
  final Set<String> nomesRecusados = {};
  String _k(String c) => p.normalize(c);

  @override
  Future<void> criarPlaceholders(String pasta, List<NovoPlaceholder> itens) async {
    if (itens.any((i) => nomesRecusados.contains(i.nome))) {
      throw const FileSystemException('O nome do arquivo, do diretório ou do rótulo do volume está incorreto');
    }
    for (final i in itens) {
      final c = _k(p.join(pasta, i.nome));
      if (FileSystemEntity.typeSync(c) != FileSystemEntityType.notFound) continue;
      if (i.pasta) {
        Directory(c).createSync(recursive: true);
      } else {
        File(c).writeAsBytesSync(const []);
      }
      ph[c] = Ph(i.identidade);
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
    return EstadoLocal(placeholder: true, emDia: e.emDia, pasta: pasta, identidade: e.identidade);
  }

  @override
  Future<bool> atualizar(String caminho, String identidade,
      {int? tamanho, int? criadoMs, int? modificadoMs, bool desidratar = false}) async {
    if (emUso.contains(_k(caminho))) throw Exception('ERROR_SHARING_VIOLATION: o arquivo está aberto em outro programa');
    final e = ph[_k(caminho)];
    if (e == null) return false;
    e.identidade = identidade;
    return true;
  }

  @override
  Future<bool> converter(String caminho, String identidade, {bool desidratar = false}) async {
    ph[_k(caminho)] = Ph(identidade);
    return true;
  }

  @override
  Future<bool> desidratar(String caminho) async => true;
  @override
  Future<List<EntradaLocal>> varrer(String raiz) async => [];
  @override
  Future<bool> marcarEmDia(String caminho) async => true;
  @override
  Future<void> mover(String de, String para) async => File(de).renameSync(para);
  @override
  Future<void> apagar(String caminho) async {
    final t = FileSystemEntity.typeSync(caminho);
    if (t == FileSystemEntityType.directory) {
      Directory(caminho).deleteSync(recursive: true);
    } else if (t != FileSystemEntityType.notFound) {
      File(caminho).deleteSync();
    }
    ph.remove(_k(caminho));
  }
}

void main() {
  late Directory tmp;
  late String raiz;
  late ApiFalsa api;
  late NativoFalso nativo;
  late ProvedorSobDemanda pr;
  late List<EventoSobDemanda> eventos;

  bool existe(String rel) => FileSystemEntity.typeSync(p.join(raiz, rel)) != FileSystemEntityType.notFound;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('ncl_falhas');
    raiz = p.join(tmp.path, 'NN Cloud');
    Directory(raiz).createSync();
    api = ApiFalsa();
    nativo = NativoFalso();
    eventos = [];
    api.nuvem
      ..['raiz'] = [
        {...ApiFalsa.item('meu', 'raiz', 'Meu Drive', pasta: true)},
        {...ApiFalsa.item('comigo', 'raiz', 'Compartilhados comigo', pasta: true)},
        {...ApiFalsa.item('drives', 'raiz', 'Drives compartilhados', pasta: true)},
      ]
      ..['meu'] = [ApiFalsa.item('i1', 'meu', 'Contas a pagar', pasta: true)]
      ..['i1'] = [
        ApiFalsa.item('i2', 'i1', 'aberto no Excel.xlsx', versao: 2),
        ApiFalsa.item('i3', 'i1', 'extrato.pdf'),
      ]
      ..['comigo'] = [ApiFalsa.item('i10', 'comigo', 'Cronograma.xlsx'), ApiFalsa.item('i11', 'comigo', 'Bruna - Teste', pasta: true)]
      ..['i11'] = [ApiFalsa.item('i12', 'i11', 'nota.txt')]
      ..['drives'] = [ApiFalsa.item('e5', 'drives', 'FINANCEIRO', pasta: true)]
      ..['e5'] = [ApiFalsa.item('i20', 'e5', 'balancete.pdf')];
    pr = ProvedorSobDemanda(
      api: api,
      nativo: nativo,
      raiz: raiz,
      arquivoEstado: File(p.join(tmp.path, 'explorer.json')),
      computador: 'NNFinanceiro',
      aoEvento: eventos.add,
    );
    // Já no disco, de uma volta anterior: a versão 1 do arquivo que está aberto no Excel.
    final aberto = p.join(raiz, 'Meu Drive', 'Contas a pagar', 'aberto no Excel.xlsx');
    Directory(p.dirname(aberto)).createSync(recursive: true);
    File(aberto).writeAsStringSync('v1');
    nativo.ph[p.normalize(p.join(raiz, 'Meu Drive'))] = Ph('meu');
    nativo.ph[p.normalize(p.dirname(aberto))] = Ph('i1');
    nativo.ph[p.normalize(aberto)] = Ph('i2:1');
    nativo.emUso.add(p.normalize(aberto));
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  test('um arquivo do Meu Drive que falha NÃO deixa Compartilhados comigo e Drives vazios', () async {
    await pr.sincronizar(completo: true);
    expect(existe('Compartilhados comigo/Cronograma.xlsx'), isTrue);
    expect(existe('Compartilhados comigo/Bruna - Teste/nota.txt'), isTrue);
    expect(existe('Drives compartilhados/FINANCEIRO/balancete.pdf'), isTrue);
    expect(existe('Meu Drive/Contas a pagar/extrato.pdf'), isTrue, reason: 'o vizinho do arquivo ruim também aparece');
    final prob = eventos.where((e) => e.tipo == 'problema').toList();
    expect(prob, hasLength(1));
    expect(prob.single.caminho, 'Meu Drive/Contas a pagar/aberto no Excel.xlsx');
    expect(prob.single.detalhe, contains('aberto em outro programa'));
    expect(pr.ancora, 'ancora1', reason: 'a âncora vale mesmo com a falha — senão a volta recomeçaria a cada ciclo');
  });

  test('com falha, o ciclo seguinte busca MUDANÇAS (não refaz a árvore); a volta completa volta depois do intervalo', () async {
    await pr.sincronizar(completo: true);
    final antes = api.chamadasFilhos['raiz'];
    await pr.sincronizar();
    expect(api.chamadasMudancas, 1);
    expect(api.chamadasFilhos['raiz'], antes, reason: 'nada de percorrer tudo a cada 30 s');

    pr.intervaloRevolta = Duration.zero;
    await pr.sincronizar(); // ainda com a data antiga agendada (10 min): mudanças
    nativo.emUso.clear(); // fecharam o Excel
    // força a revolta agora
    await pr.sincronizar(completo: true);
    expect(api.chamadasFilhos['raiz'], antes! + 1);
    expect(nativo.ph[p.normalize(p.join(raiz, 'Meu Drive', 'Contas a pagar', 'aberto no Excel.xlsx'))]!.identidade, 'i2:2',
        reason: 'na volta seguinte, sem o Excel aberto, a versão nova chega');
  });

  test('a volta completa agendada acontece sozinha quando o intervalo passa', () async {
    pr.intervaloRevolta = Duration.zero;
    await pr.sincronizar(completo: true); // falha → revolta agendada para "agora"
    final antes = api.chamadasFilhos['raiz']!;
    await pr.sincronizar();
    expect(api.chamadasFilhos['raiz'], antes + 1, reason: 'revolta pela agenda, sem precisar de "completo"');
    expect(api.chamadasMudancas, 0);
  });

  test('sem falhas não agenda volta completa: só mudanças', () async {
    nativo.emUso.clear();
    pr.intervaloRevolta = Duration.zero;
    await pr.sincronizar(completo: true);
    final antes = api.chamadasFilhos['raiz']!;
    await pr.sincronizar();
    await pr.sincronizar();
    expect(api.chamadasFilhos['raiz'], antes);
    expect(api.chamadasMudancas, 2);
  });

  test('um nome que o lote recusa: os outros da pasta aparecem', () async {
    nativo.nomesRecusados.add('Cronograma.xlsx');
    await pr.sincronizar(completo: true);
    expect(existe('Compartilhados comigo/Cronograma.xlsx'), isFalse);
    expect(existe('Compartilhados comigo/Bruna - Teste/nota.txt'), isTrue);
    expect(eventos.where((e) => e.tipo == 'problema').map((e) => e.caminho), contains('Compartilhados comigo/Cronograma.xlsx'));
  });

  test('erro numa SUBPASTA (não de rede) vira problema e as outras seguem', () async {
    api
      ..idErro = 'i1'
      ..erroFilhos = const ApiErro(404, 'Item não encontrado.');
    await pr.sincronizar(completo: true);
    expect(existe('Drives compartilhados/FINANCEIRO/balancete.pdf'), isTrue);
    expect(eventos.any((e) => e.tipo == 'problema' && e.caminho == 'Meu Drive/Contas a pagar'), isTrue);
    expect(pr.ancora, isNotNull);
  });

  test('queda de rede INTERROMPE a volta e a âncora não anda (a próxima tenta tudo)', () async {
    api
      ..idErro = 'comigo'
      ..erroFilhos = const ApiErro(0, 'Sem conexão', queda: true);
    await expectLater(pr.sincronizar(completo: true), throwsA(isA<ApiErro>()));
    expect(pr.ancora, isNull);
  });

  test('nas mudanças, o item que falha não trava a fila: os outros entram e a âncora anda', () async {
    nativo.emUso.clear();
    await pr.sincronizar(completo: true);
    final aberto = p.normalize(p.join(raiz, 'Meu Drive', 'Contas a pagar', 'aberto no Excel.xlsx'));
    nativo.emUso.add(aberto);
    api.proximasMudancas = [
      ApiFalsa.item('i2', 'i1', 'aberto no Excel.xlsx', versao: 3), // aberto de novo: falha
      ApiFalsa.item('i30', 'comigo', 'Novo compartilhado.docx'),
    ];
    final antes = pr.ancora;
    await pr.sincronizar();
    expect(existe('Compartilhados comigo/Novo compartilhado.docx'), isTrue);
    expect(pr.ancora, isNot(antes));
    expect(eventos.where((e) => e.tipo == 'problema').map((e) => e.caminho), contains('Meu Drive/Contas a pagar/aberto no Excel.xlsx'));
  });
}
