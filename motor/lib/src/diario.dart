// O DIÁRIO LOCAL de um par: a árvore da nuvem conhecida, o cursor das
// mudanças, a BASE e o cache de impressões. É a fonte de verdade do aplicativo;
// o MySQL (pela API) é a RÉPLICA.
//
// ⚠️ Gravado de forma ATÔMICA (arquivo temporário + flush + rename): um
// desligamento no meio da gravação deixa o diário antigo inteiro, nunca meio
// diário. Diário ilegível = perdido → o par entra em JUNÇÃO SEGURA (nenhuma
// exclusão até um ciclo limpo).
// ⚠️ A base só é gravada DEPOIS do efeito confirmado (arquivo baixado e
// renomeado, envio concluído): gravar antes faria a próxima rodada achar que
// os dois lados concordam quando não concordam.
import 'dart:convert';
import 'dart:io';

import 'modelos.dart';

class ImpressaoCache {
  final int tamanho, mtimeMs;
  final String hex;
  const ImpressaoCache(this.tamanho, this.mtimeMs, this.hex);
}

class Diario {
  final int par;
  int cursor = 0;
  bool arvoreCompleta = false;      // a árvore inicial terminou de ser listada?
  int arvoreDepoisDe = 0;           // paginação da listagem inicial
  bool juncaoSegura = false;
  final ArvoreNuvem nuvem = ArvoreNuvem();
  final Map<String, ItemBase> base = {};
  final Map<String, ImpressaoCache> impressoes = {};
  /// Linhas da base ainda não enviadas ao MySQL (item_id → linha) e remoções.
  final Map<int, ItemBase> baseAEnviar = {};
  final Set<int> baseARemover = {};

  Diario(this.par);

  static File arquivo(Directory pasta) => File('${pasta.path}/diario.json');

  /// null = não existe ou ilegível (o chamador entra em junção segura).
  static Diario? ler(Directory pasta, int par) {
    final f = arquivo(pasta);
    if (!f.existsSync()) return null;
    try {
      final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      if (j['par'] != par || j['versao'] != 1) return null;
      final d = Diario(par)
        ..cursor = j['cursor'] as int
        ..arvoreCompleta = j['arvore_completa'] as bool
        ..arvoreDepoisDe = (j['arvore_depois_de'] as int?) ?? 0
        ..juncaoSegura = (j['juncao_segura'] as bool?) ?? false;
      d.nuvem.deJson(j['nuvem'] as List);
      for (final b in (j['base'] as List)) {
        final ib = ItemBase.deJson((b as Map).cast<String, dynamic>());
        d.base[ib.caminho] = ib;
      }
      (j['impressoes'] as Map).forEach((k, v) {
        final l = v as List;
        d.impressoes[k as String] = ImpressaoCache(l[0] as int, l[1] as int, l[2] as String);
      });
      for (final b in ((j['base_a_enviar'] as List?) ?? [])) {
        final ib = ItemBase.deJson((b as Map).cast<String, dynamic>());
        d.baseAEnviar[ib.itemId] = ib;
      }
      d.baseARemover.addAll(((j['base_a_remover'] as List?) ?? []).cast<int>());
      return d;
    } catch (_) {
      return null;
    }
  }

  void gravar(Directory pasta) {
    pasta.createSync(recursive: true);
    final j = {
      'versao': 1,
      'par': par,
      'cursor': cursor,
      'arvore_completa': arvoreCompleta,
      'arvore_depois_de': arvoreDepoisDe,
      'juncao_segura': juncaoSegura,
      'nuvem': nuvem.paraJson(),
      'base': base.values.map((b) => b.paraJson()).toList(),
      'impressoes': {for (final e in impressoes.entries) e.key: [e.value.tamanho, e.value.mtimeMs, e.value.hex]},
      'base_a_enviar': baseAEnviar.values.map((b) => b.paraJson()).toList(),
      'base_a_remover': baseARemover.toList(),
    };
    final tmp = File('${pasta.path}/diario.json.tmp');
    final raf = tmp.openSync(mode: FileMode.write);
    try {
      raf.writeFromSync(utf8.encode(jsonEncode(j)));
      raf.flushSync();
    } finally {
      raf.closeSync();
    }
    tmp.renameSync(arquivo(pasta).path);
  }

  // ---------- Base ----------

  void porBase(ItemBase b) {
    base.removeWhere((k, v) => v.itemId == b.itemId && k != b.caminho);
    base[b.caminho] = b;
    baseAEnviar[b.itemId] = b;
    baseARemover.remove(b.itemId);
  }

  void tirarBase(String caminho, {bool comFilhos = false}) {
    for (final k in base.keys.toList()) {
      if (k == caminho || (comFilhos && dentroDe(k, caminho))) {
        final b = base.remove(k)!;
        baseAEnviar.remove(b.itemId);
        baseARemover.add(b.itemId);
      }
    }
  }

  /// Uma pasta (ou arquivo) mudou de caminho: a base de tudo abaixo acompanha.
  void moverBase(String de, String para) {
    for (final k in base.keys.toList()) {
      if (k == de || dentroDe(k, de)) {
        final b = base.remove(k)!.noCaminho(para + k.substring(de.length));
        base[b.caminho] = b;
        baseAEnviar[b.itemId] = b;
      }
    }
    for (final k in impressoes.keys.toList()) {
      if (k == de || dentroDe(k, de)) {
        impressoes[para + k.substring(de.length)] = impressoes.remove(k)!;
      }
    }
  }
}
