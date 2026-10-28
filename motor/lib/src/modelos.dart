// As três visões que a sincronização compara, para cada pasta sincronizada:
//   NUVEM  — a árvore viva da raiz do par (ids, pai, versão);
//   LOCAL  — o que a varredura achou no computador (tamanho, data);
//   BASE   — o último estado em que os dois lados concordavam.
// Caminhos são RELATIVOS à raiz, com "/" e em NFC.
import 'nomes.dart';

enum Tipo { arquivo, pasta }

Tipo tipoDe(String s) => s == 'pasta' ? Tipo.pasta : Tipo.arquivo;
String nomeTipo(Tipo t) => t == Tipo.pasta ? 'pasta' : 'arquivo';

class ItemNuvem {
  final int id;
  int? pai;           // null = a raiz do par
  final Tipo tipo;
  String nome;
  int? tamanho;
  String? impressao;
  int versao;
  int? mtimeMs;
  int rev;

  ItemNuvem({required this.id, this.pai, required this.tipo, required this.nome, this.tamanho, this.impressao,
      this.versao = 0, this.mtimeMs, this.rev = 0});

  factory ItemNuvem.deJson(Map<String, dynamic> j) => ItemNuvem(
        id: j['id'] as int,
        pai: j['pai'] as int?,
        tipo: tipoDe(j['tipo'] as String),
        nome: nfc(j['nome'] as String),
        tamanho: j['tamanho'] as int?,
        impressao: j['impressao'] as String?,
        versao: (j['versao'] as int?) ?? 0,
        mtimeMs: j['mtime_ms'] as int?,
        rev: (j['rev'] as int?) ?? 0,
      );

  Map<String, dynamic> paraJson() => {
        'id': id, 'pai': pai, 'tipo': nomeTipo(tipo), 'nome': nome, 'tamanho': tamanho,
        'impressao': impressao, 'versao': versao, 'mtime_ms': mtimeMs, 'rev': rev,
      };
}

class ItemLocal {
  final String caminho;
  final Tipo tipo;
  final int tamanho;
  final int mtimeMs;
  const ItemLocal(this.caminho, this.tipo, this.tamanho, this.mtimeMs);
}

class ItemBase {
  String caminho;
  final int itemId;
  final Tipo tipo;
  final int? tamanho;
  final int? mtimeMs;      // a data LOCAL no momento em que os dois lados concordaram
  final String? impressao;
  final int? versao;

  ItemBase({required this.caminho, required this.itemId, required this.tipo, this.tamanho, this.mtimeMs, this.impressao, this.versao});

  factory ItemBase.deJson(Map<String, dynamic> j) => ItemBase(
        caminho: j['caminho'] as String,
        itemId: j['item_id'] as int,
        tipo: tipoDe(j['tipo'] as String),
        tamanho: j['tamanho'] as int?,
        mtimeMs: j['mtime_ms'] as int?,
        impressao: j['impressao'] as String?,
        versao: j['versao'] as int?,
      );

  Map<String, dynamic> paraJson() => {
        'caminho': caminho, 'item_id': itemId, 'tipo': nomeTipo(tipo), 'tamanho': tamanho,
        'mtime_ms': mtimeMs, 'impressao': impressao, 'versao': versao,
      };

  ItemBase noCaminho(String c) =>
      ItemBase(caminho: c, itemId: itemId, tipo: tipo, tamanho: tamanho, mtimeMs: mtimeMs, impressao: impressao, versao: versao);
}

/// A árvore da nuvem de um par, com os caminhos montados a partir do pai.
class ArvoreNuvem {
  final Map<int, ItemNuvem> itens = {};

  void limpar() => itens.clear();

  void por(ItemNuvem i) => itens[i.id] = i;

  /// Tira o item e TUDO abaixo dele (uma pasta que saiu leva os filhos — o
  /// servidor registra UMA mudança por operação, não uma por descendente).
  void tirar(int id) {
    final fila = [id];
    while (fila.isNotEmpty) {
      final x = fila.removeLast();
      itens.remove(x);
      fila.addAll(itens.values.where((i) => i.pai == x).map((i) => i.id));
    }
  }

  /// Caminho relativo à raiz, ou null se a cadeia de pais está incompleta.
  String? caminhoDe(int id, [Map<int, String?>? memo]) {
    memo ??= {};
    if (memo.containsKey(id)) return memo[id];
    final partes = <String>[];
    var atual = itens[id];
    final vistos = <int>{};
    while (atual != null) {
      if (!vistos.add(atual.id)) return memo[id] = null;   // ciclo: não confiar
      partes.add(atual.nome);
      if (atual.pai == null) break;
      atual = itens[atual.pai];
      if (atual == null) return memo[id] = null;          // pai desconhecido
    }
    return memo[id] = partes.reversed.join('/');
  }

  /// Caminho → item (só os de cadeia completa).
  Map<String, ItemNuvem> porCaminho() {
    final memo = <int, String?>{};
    final out = <String, ItemNuvem>{};
    for (final i in itens.values) {
      final c = caminhoDe(i.id, memo);
      if (c != null) out[c] = i;
    }
    return out;
  }

  List<Map<String, dynamic>> paraJson() => itens.values.map((i) => i.paraJson()).toList();

  void deJson(List<dynamic> l) {
    itens.clear();
    for (final j in l) {
      final i = ItemNuvem.deJson((j as Map).cast<String, dynamic>());
      itens[i.id] = i;
    }
  }
}

String paiDe(String caminho) {
  final p = caminho.lastIndexOf('/');
  return p < 0 ? '' : caminho.substring(0, p);
}

String nomeDe(String caminho) {
  final p = caminho.lastIndexOf('/');
  return p < 0 ? caminho : caminho.substring(p + 1);
}

bool dentroDe(String caminho, String pasta) => pasta.isEmpty || caminho.startsWith('$pasta/');
