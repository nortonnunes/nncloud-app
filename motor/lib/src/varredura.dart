// A VARREDURA da pasta local de um par.
//
// ⚠️ Atalhos e links simbólicos NÃO são seguidos (um link para "/" varreria o
// disco inteiro; um link para dentro da própria pasta, para sempre).
// ⚠️ O macOS entrega nomes em NFD: a chave é o NFC, e `real` guarda o nome
// como está no disco (é por ele que o arquivo é aberto).
// ⚠️ O MARCADOR (`.nncloud`) na raiz diz "esta pasta é o par N". Se a raiz ou
// o marcador sumirem (disco desmontado, pasta renomeada), o par PARA — pasta
// sumida nunca vira "apague tudo na nuvem".
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'ignorados.dart';
import 'modelos.dart';
import 'nomes.dart';

const String nomeMarcador = '.nncloud';
const String prefixoTemporario = '.nncloud-tmp-';

class ResultadoVarredura {
  final Map<String, ItemLocal> itens = {};
  /// caminho NFC → caminho real no disco (relativo).
  final Map<String, String> real = {};
  /// Itens que não puderam ser lidos (sem permissão…).
  final Map<String, String> problemas = {};
  /// Temporários do próprio app (download interrompido) — o sincronizador os limpa.
  final List<File> temporarios = [];
  int arquivos = 0, pastas = 0, bytes = 0;
}

enum SituacaoRaiz { ok, semRaiz, semMarcador, marcadorDeOutro }

class Varredura {
  final Ignorados ignorados;
  Varredura(this.ignorados);

  static SituacaoRaiz conferirRaiz(String raiz, int par) {
    final d = Directory(raiz);
    if (!d.existsSync()) return SituacaoRaiz.semRaiz;
    final m = File('$raiz${Platform.pathSeparator}$nomeMarcador');
    if (!m.existsSync()) return SituacaoRaiz.semMarcador;
    try {
      final j = jsonDecode(m.readAsStringSync()) as Map<String, dynamic>;
      return j['par'] == par ? SituacaoRaiz.ok : SituacaoRaiz.marcadorDeOutro;
    } catch (_) {
      return SituacaoRaiz.marcadorDeOutro;
    }
  }

  static void gravarMarcador(String raiz, int par) {
    final m = File('$raiz${Platform.pathSeparator}$nomeMarcador');
    m.writeAsStringSync(jsonEncode({'par': par, 'aviso': 'Pasta sincronizada pelo NN Cloud. Não apague este arquivo.'}));
    if (Platform.isWindows) {
      Process.runSync('attrib', ['+h', m.path]);
    }
  }

  ResultadoVarredura varrer(String raiz) {
    final r = ResultadoVarredura();
    _pasta(Directory(raiz), '', '', r, 0);
    return r;
  }

  void _pasta(Directory d, String rel, String relReal, ResultadoVarredura r, int nivel) {
    if (nivel > 64) {
      r.problemas[rel] = 'pastas demais uma dentro da outra';
      return;
    }
    List<FileSystemEntity> filhos;
    try {
      filhos = d.listSync(followLinks: false);
    } on FileSystemException catch (e) {
      if (rel.isNotEmpty) r.problemas[rel] = 'sem permissão para ler a pasta (${e.osError?.message ?? e.message})';
      return;
    }
    for (final f in filhos) {
      final nomeDisco = p.basename(f.path);
      final nome = nfc(nomeDisco);
      if (rel.isEmpty && nome == nomeMarcador) continue;
      if (nome.startsWith(prefixoTemporario)) {
        if (f is File) r.temporarios.add(f);
        continue;
      }
      if (ignorados.nome(nome)) continue;
      final c = rel.isEmpty ? nome : '$rel/$nome';
      final cReal = relReal.isEmpty ? nomeDisco : '$relReal/$nomeDisco';
      if (f is Link) continue;
      try {
        if (f is Directory) {
          r.itens[c] = ItemLocal(c, Tipo.pasta, 0, 0);
          r.real[c] = cReal;
          r.pastas++;
          _pasta(f, c, cReal, r, nivel + 1);
        } else if (f is File) {
          final st = f.statSync();
          r.itens[c] = ItemLocal(c, Tipo.arquivo, st.size, st.modified.millisecondsSinceEpoch);
          r.real[c] = cReal;
          r.arquivos++;
          r.bytes += st.size;
        }
      } on FileSystemException catch (e) {
        r.problemas[c] = 'não foi possível ler (${e.osError?.message ?? e.message})';
      }
    }
  }
}
