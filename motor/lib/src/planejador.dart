// O PLANEJADOR: compara nuvem × computador × base e decide o que fazer.
//
// É uma função (quase) pura — não toca em disco nem em rede; quem precisa da
// impressão de um arquivo local a pede pelo `impressaoLocal`. Por isso todas as
// regras são testadas em tabela (`test/planejador_test.dart`).
//
// Regras (para cada caminho; a comparação ignora maiúsculas, como NTFS e APFS):
//   só mudou no PC ............ envia (com a versão de base)
//   só mudou na nuvem ......... baixa
//   mudou nos dois ............ impressão igual → só a base; diferente → CONFLITO
//                               (a nuvem fica com o nome; a versão do PC vira
//                               "nome (conflito de PC data).ext")
//   apagado no PC ............. vai para a lixeira da nuvem
//   apagado na nuvem .......... vai para a lixeira LOCAL do aplicativo
//   mudança × exclusão ........ a mudança vence (nos dois sentidos)
//   movido/renomeado .......... detectado (id na nuvem; tamanho + impressão no PC)
//   base vazia ................ compara impressões; o que é igual não trafega
//
// ⚠️ Proteções que moram aqui:
//   - `juncaoSegura` (diário perdido, app reinstalado): NENHUMA exclusão em lado
//     nenhum — o que falta de um lado é restaurado do outro;
//   - área só de leitura: o que mudou no PC vira PROBLEMA (nunca apaga nada), e
//     o que foi apagado no PC é baixado de novo;
//   - nome que o Windows não aceita: PROBLEMA, o arquivo fica só no computador.
// A trava de EXCLUSÃO EM MASSA fica no motor, que conta as exclusões do plano.
import 'modelos.dart';
import 'nomes.dart';

sealed class Acao {
  String get caminho;
  int get ordem;   // menor primeiro
}

class MoverLocal extends Acao {
  final String de, para;
  final int itemId;
  final Tipo tipo;
  MoverLocal(this.de, this.para, this.itemId, this.tipo);
  @override
  String get caminho => para;
  @override
  int get ordem => 0;
  @override
  String toString() => 'MoverLocal($de → $para)';
}

class MoverNuvem extends Acao {
  final String de, para;
  final int itemId;
  final Tipo tipo;
  MoverNuvem(this.de, this.para, this.itemId, this.tipo);
  @override
  String get caminho => para;
  @override
  int get ordem => 1;
  @override
  String toString() => 'MoverNuvem($de → $para)';
}

class CriarPastaLocal extends Acao {
  @override
  final String caminho;
  final int itemId;
  CriarPastaLocal(this.caminho, this.itemId);
  @override
  int get ordem => 2;
  @override
  String toString() => 'CriarPastaLocal($caminho)';
}

class CriarPastaNuvem extends Acao {
  @override
  final String caminho;
  CriarPastaNuvem(this.caminho);
  @override
  int get ordem => 2;
  @override
  String toString() => 'CriarPastaNuvem($caminho)';
}

class EnviarNovo extends Acao {
  @override
  final String caminho;
  EnviarNovo(this.caminho);
  @override
  int get ordem => 3;
  @override
  String toString() => 'EnviarNovo($caminho)';
}

class EnviarAtualizacao extends Acao {
  @override
  final String caminho;
  final int itemId;
  final int baseVersao;
  EnviarAtualizacao(this.caminho, this.itemId, this.baseVersao);
  @override
  int get ordem => 3;
  @override
  String toString() => 'EnviarAtualizacao($caminho)';
}

class Baixar extends Acao {
  @override
  final String caminho;
  final ItemNuvem item;
  /// O que se espera achar no PC antes de substituir (null = nada). Se o
  /// arquivo local não bate, o executor NÃO substitui — vira conflito.
  final ItemBase? esperado;
  Baixar(this.caminho, this.item, this.esperado);
  @override
  int get ordem => 3;
  @override
  String toString() => 'Baixar($caminho)';
}

class Conflito extends Acao {
  @override
  final String caminho;
  final ItemNuvem item;
  Conflito(this.caminho, this.item);
  @override
  int get ordem => 3;
  @override
  String toString() => 'Conflito($caminho)';
}

class SoBase extends Acao {
  @override
  final String caminho;
  final ItemBase base;
  SoBase(this.caminho, this.base);
  @override
  int get ordem => 3;
  @override
  String toString() => 'SoBase($caminho)';
}

class LixeiraNuvem extends Acao {
  @override
  final String caminho;
  final int itemId;
  final Tipo tipo;
  LixeiraNuvem(this.caminho, this.itemId, this.tipo);
  @override
  int get ordem => 4;
  @override
  String toString() => 'LixeiraNuvem($caminho)';
}

class LixeiraLocal extends Acao {
  @override
  final String caminho;
  final Tipo tipo;
  final ItemBase? esperado;
  LixeiraLocal(this.caminho, this.tipo, this.esperado);
  @override
  int get ordem => 4;
  @override
  String toString() => 'LixeiraLocal($caminho)';
}

class RemoverBase extends Acao {
  @override
  final String caminho;
  RemoverBase(this.caminho);
  @override
  int get ordem => 5;
  @override
  String toString() => 'RemoverBase($caminho)';
}

class Problema extends Acao {
  @override
  final String caminho;
  final String motivo;
  Problema(this.caminho, this.motivo);
  @override
  int get ordem => 6;
  @override
  String toString() => 'Problema($caminho: $motivo)';
}

class Plano {
  final List<Acao> acoes;
  Plano(this.acoes);
  int get exclusoesNuvem => acoes.whereType<LixeiraNuvem>().length;
  int get exclusoesLocais => acoes.whereType<LixeiraLocal>().length;
  bool get vazio => acoes.isEmpty;
  List<T> de<T extends Acao>() => acoes.whereType<T>().toList();
}

class _Linha {
  String? pL, pC, pB;
  ItemLocal? l;
  ItemNuvem? c;
  ItemBase? b;
  String get caminho => pL ?? pC ?? pB!;
  int get nivel => '/'.allMatches(caminho).length;
}

Future<Plano> planejar({
  required Map<String, ItemNuvem> nuvem,
  required Map<String, ItemLocal> local,
  required Map<String, ItemBase> base,
  required Future<String?> Function(String caminho) impressaoLocal,
  bool juncaoSegura = false,
  bool podeEditar = true,
}) async {
  final acoes = <Acao>[];
  // Cópias de trabalho por caminho EXATO (os movimentos as reescrevem).
  final n = Map<String, ItemNuvem>.of(nuvem);
  final l = Map<String, ItemLocal>.of(local);
  final b = <String, ItemBase>{for (final e in base.entries) e.key: e.value};

  Map<String, String> chaves(Map<String, Object> m) => {for (final k in m.keys) chaveCaminho(k): k};

  void reescrever<T>(Map<String, T> m, String de, String para, T Function(T, String) novo) {
    for (final k in m.keys.toList()) {
      if (k == de || dentroDe(k, de)) {
        final v = m.remove(k) as T;
        final nk = para + k.substring(de.length);
        m[nk] = novo(v, nk);
      }
    }
  }

  ItemLocal moveLocal(ItemLocal i, String c) => ItemLocal(c, i.tipo, i.tamanho, i.mtimeMs);
  ItemBase moveBase(ItemBase i, String c) => i.noCaminho(c);
  ItemNuvem mesmo(ItemNuvem i, String c) => i;

  // ---------- 1. Movidos/renomeados NA NUVEM (pelo id) ----------
  {
    final caminhoNuvemPorId = {for (final e in n.entries) e.value.id: e.key};
    final ordenados = b.values.toList()..sort((x, y) => '/'.allMatches(x.caminho).length.compareTo('/'.allMatches(y.caminho).length));
    var kl = chaves(l);
    for (final be in ordenados) {
      final p = be.caminho;
      if (!b.containsKey(p) || b[p]!.itemId != be.itemId) continue;   // já reescrito por um pai movido
      final q = caminhoNuvemPorId[be.itemId];
      if (q == null || q == p) continue;
      final temLocal = kl[chaveCaminho(p)];
      if (temLocal == null || l[temLocal]!.tipo != be.tipo) continue;
      final destinoOcupado = kl[chaveCaminho(q)];
      if (destinoOcupado != null && chaveCaminho(q) != chaveCaminho(p)) continue;   // não sobrescreve
      acoes.add(MoverLocal(temLocal, q, be.itemId, be.tipo));
      reescrever<ItemLocal>(l, temLocal, q, moveLocal);
      reescrever<ItemBase>(b, p, q, moveBase);
      kl = chaves(l);
    }
  }

  // ---------- 2. Movidos/renomeados NO PC (tamanho + impressão) ----------
  if (podeEditar) {
    final kn = chaves(n);
    final kb = chaves(b);
    final ordenados = b.values.toList()
      ..sort((x, y) {
        final t = (x.tipo == Tipo.pasta ? 0 : 1).compareTo(y.tipo == Tipo.pasta ? 0 : 1);
        return t != 0 ? t : '/'.allMatches(x.caminho).length.compareTo('/'.allMatches(y.caminho).length);
      });
    final usados = <String>{};
    final kl = chaves(l);   // `l` não muda nesta etapa
    for (final be in ordenados) {
      final p = be.caminho;
      if (!b.containsKey(p) || b[p]!.itemId != be.itemId) continue;
      final cNuvem = n[kn[chaveCaminho(p)] ?? ''];
      if (cNuvem == null || cNuvem.id != be.itemId) continue;          // a nuvem também mexeu
      if (be.tipo == Tipo.arquivo && cNuvem.versao != be.versao) continue;
      final localExato = kl[chaveCaminho(p)];
      if (localExato != null) {
        // Só a caixa mudou no PC ("relatorio.pdf" → "Relatorio.pdf").
        if (localExato != p && kn[chaveCaminho(p)] == p && l[localExato]!.tipo == be.tipo) {
          acoes.add(MoverNuvem(p, localExato, be.itemId, be.tipo));
          reescrever<ItemBase>(b, p, localExato, moveBase);
          reescrever<ItemNuvem>(n, p, localExato, mesmo);
        }
        continue;
      }
      // Sumiu do PC: procura um item NOVO (fora da base e da nuvem) que seja ele.
      String? achado;
      for (final cand in l.values) {
        final kc = chaveCaminho(cand.caminho);
        if (cand.tipo != be.tipo || usados.contains(kc) || kb.containsKey(kc) || kn.containsKey(kc)) continue;
        if (be.tipo == Tipo.arquivo) {
          if (be.tamanho == null || cand.tamanho != be.tamanho || be.impressao == null) continue;
          if (await impressaoLocal(cand.caminho) == be.impressao) {
            achado = cand.caminho;
            break;
          }
        } else {
          // Pasta: todos os arquivos que ela tinha estão no candidato, com o mesmo tamanho.
          final filhos = b.values.where((x) => x.tipo == Tipo.arquivo && dentroDe(x.caminho, p)).toList();
          if (filhos.isEmpty) continue;
          final ok = filhos.every((x) {
            final rel = x.caminho.substring(p.length);
            final li = l[kl[chaveCaminho(cand.caminho + rel)] ?? ''];
            return li != null && li.tamanho == x.tamanho;
          });
          if (ok) {
            achado = cand.caminho;
            break;
          }
        }
      }
      if (achado == null) continue;
      final destinoInvalido = achado.split('/').map(motivoNome).whereType<String>().firstOrNull;
      if (destinoInvalido != null) continue;   // segue o caminho comum (vira problema/lixeira)
      usados.add(chaveCaminho(achado));
      acoes.add(MoverNuvem(p, achado, be.itemId, be.tipo));
      reescrever<ItemBase>(b, p, achado, moveBase);
      reescrever<ItemNuvem>(n, p, achado, mesmo);
    }
  }

  // ---------- 3. Caminho a caminho ----------
  final linhas = <String, _Linha>{};
  _Linha linha(String k) => linhas.putIfAbsent(k, _Linha.new);
  for (final e in l.entries) {
    linha(chaveCaminho(e.key))
      ..pL = e.key
      ..l = e.value;
  }
  for (final e in n.entries) {
    linha(chaveCaminho(e.key))
      ..pC = e.key
      ..c = e.value;
  }
  for (final e in b.entries) {
    linha(chaveCaminho(e.key))
      ..pB = e.key
      ..b = e.value;
  }

  final decisao = <String, Acao>{};       // chave → ação principal
  final extras = <Acao>[];

  String? invalido(String c) {
    for (final parte in c.split('/')) {
      final m = motivoNome(parte);
      if (m != null) return 'não pode ir para a nuvem: $m';
    }
    return null;
  }

  ItemBase baseDe(String c, ItemNuvem cn, ItemLocal li, String? imp) => ItemBase(
      caminho: c, itemId: cn.id, tipo: cn.tipo, tamanho: li.tipo == Tipo.arquivo ? li.tamanho : null,
      mtimeMs: li.tipo == Tipo.arquivo ? li.mtimeMs : null, impressao: imp ?? cn.impressao, versao: cn.versao);

  // Arquivos primeiro.
  for (final e in linhas.entries.where((e) => (e.value.l?.tipo ?? e.value.c?.tipo ?? e.value.b!.tipo) == Tipo.arquivo)) {
    final k = e.key;
    final x = e.value;
    final li = x.l, cn = x.c, be = x.b;
    if (li != null && cn != null && li.tipo != cn.tipo) {
      decisao[k] = Problema(x.caminho, 'existe uma pasta e um arquivo com este nome');
      continue;
    }
    final lc = li != null && (be == null || li.tamanho != be.tamanho || li.mtimeMs != be.mtimeMs);
    final cc = cn != null && (be == null || cn.id != be.itemId || cn.versao != be.versao);

    if (li != null && cn != null) {
      if (!lc && !cc) continue;
      if (lc && !cc) {
        final inv = invalido(x.pL!);
        decisao[k] = !podeEditar
            ? Problema(x.pL!, 'a pasta na nuvem é só de leitura — a alteração ficou só no computador')
            : inv != null
                ? Problema(x.pL!, inv)
                : EnviarAtualizacao(x.pL!, cn.id, cn.versao);
        continue;
      }
      if (!lc && cc) {
        decisao[k] = Baixar(x.pL!, cn, be);
        continue;
      }
      // Mudou nos dois (ou apareceu nos dois sem base).
      if (cn.tamanho == li.tamanho && cn.impressao != null) {
        final imp = await impressaoLocal(x.pL!);
        if (imp == cn.impressao) {
          decisao[k] = SoBase(x.pL!, baseDe(x.pL!, cn, li, imp));
          continue;
        }
      }
      decisao[k] = !podeEditar ? Baixar(x.pL!, cn, be) : Conflito(x.pL!, cn);
      continue;
    }
    if (li != null && cn == null) {
      final inv = invalido(x.pL!);
      if (be == null || lc || juncaoSegura) {
        decisao[k] = !podeEditar
            ? Problema(x.pL!, 'a pasta na nuvem é só de leitura — o arquivo ficou só no computador')
            : inv != null
                ? Problema(x.pL!, inv)
                : EnviarNovo(x.pL!);
      } else {
        decisao[k] = LixeiraLocal(x.pL!, Tipo.arquivo, be);
      }
      continue;
    }
    if (li == null && cn != null) {
      if (be == null || cc || juncaoSegura || !podeEditar) {
        decisao[k] = Baixar(x.pC!, cn, null);
      } else {
        decisao[k] = LixeiraNuvem(x.pC!, cn.id, Tipo.arquivo);
      }
      continue;
    }
    decisao[k] = RemoverBase(x.pB!);   // sumiu dos dois lados
  }

  // Pastas, das mais fundas para as mais rasas (a decisão da pasta depende dos filhos).
  final pastas = linhas.entries.where((e) => (e.value.l?.tipo ?? e.value.c?.tipo ?? e.value.b!.tipo) == Tipo.pasta).toList()
    ..sort((x, y) => y.value.nivel.compareTo(x.value.nivel));
  for (final e in pastas) {
    final k = e.key;
    final x = e.value;
    final li = x.l, cn = x.c, be = x.b;
    if (li != null && cn != null && li.tipo != cn.tipo) {
      decisao[k] = Problema(x.caminho, 'existe uma pasta e um arquivo com este nome');
      continue;
    }
    bool soFilhos(bool Function(Acao) ok) => decisao.entries.where((d) => dentroDe(d.key, k)).every((d) => ok(d.value));
    if (li != null && cn != null) {
      if (be == null) decisao[k] = SoBase(x.pL!, ItemBase(caminho: x.pL!, itemId: cn.id, tipo: Tipo.pasta));
      continue;
    }
    if (li != null && cn == null) {
      if (be != null && !juncaoSegura && soFilhos((a) => a is LixeiraLocal || a is RemoverBase)) {
        decisao[k] = LixeiraLocal(x.pL!, Tipo.pasta, be);
      } else {
        final inv = invalido(x.pL!);
        if (be != null) extras.add(RemoverBase(x.pB!));
        decisao[k] = !podeEditar
            ? Problema(x.pL!, 'a pasta na nuvem é só de leitura')
            : inv != null
                ? Problema(x.pL!, inv)
                : CriarPastaNuvem(x.pL!);
      }
      continue;
    }
    if (li == null && cn != null) {
      if (be != null && !juncaoSegura && podeEditar && soFilhos((a) => a is LixeiraNuvem || a is RemoverBase)) {
        decisao[k] = LixeiraNuvem(x.pC!, cn.id, Tipo.pasta);
      } else {
        decisao[k] = CriarPastaLocal(x.pC!, cn.id);
      }
      continue;
    }
    decisao[k] = RemoverBase(x.pB!);
  }

  // Uma pasta que vai inteira para a lixeira leva os filhos: as ações deles saem.
  final lixPastas = decisao.entries.where((d) => (d.value is LixeiraLocal || d.value is LixeiraNuvem) &&
      (d.value is LixeiraLocal ? (d.value as LixeiraLocal).tipo : (d.value as LixeiraNuvem).tipo) == Tipo.pasta).map((d) => d.key).toList();
  for (final pk in lixPastas) {
    for (final dk in decisao.keys.toList()) {
      if (dk != pk && dentroDe(dk, pk) && (decisao[dk] is LixeiraLocal || decisao[dk] is LixeiraNuvem)) {
        decisao[dk] = RemoverBase(linhas[dk]!.pB ?? linhas[dk]!.caminho);
      }
    }
  }
  // Base de filhos de pasta que vai para a lixeira só sai se existia.
  decisao.removeWhere((k, a) => a is RemoverBase && linhas[k]?.b == null);

  acoes.addAll(decisao.values);
  acoes.addAll(extras);
  acoes.sort((x, y) {
    final o = x.ordem.compareTo(y.ordem);
    if (o != 0) return o;
    final nx = '/'.allMatches(x.caminho).length, ny = '/'.allMatches(y.caminho).length;
    // Criar: rasos primeiro. Apagar: fundos primeiro.
    return x.ordem == 4 ? ny.compareTo(nx) : nx.compareTo(ny);
  });
  return Plano(acoes);
}
