// Regras de NOME — contrato com `app/Core/NnCloud/Nome.php`. Mudou lá, mude aqui.
//
// ⚠️ `validar` é ESTRITO e não reescreve nada além do NFC: se o aplicativo
// "corrigisse" um nome, o arquivo voltaria da nuvem com outro nome e a
// sincronização o trataria como novo, num vai e vem sem fim. Nome que não
// serve vira PROBLEMA na tela, e o arquivo fica só no computador.
import 'dart:convert';

import 'package:unorm_dart/unorm_dart.dart' as unorm;

const int maxBytesNome = 255;
const List<String> proibidos = ['/', '\\', ':', '*', '?', '"', '<', '>', '|'];
const Set<String> _reservados = {
  'con', 'prn', 'aux', 'nul', //
  'com1', 'com2', 'com3', 'com4', 'com5', 'com6', 'com7', 'com8', 'com9',
  'lpt1', 'lpt2', 'lpt3', 'lpt4', 'lpt5', 'lpt6', 'lpt7', 'lpt8', 'lpt9',
};

/// Normaliza para NFC (o macOS entrega muito nome em NFD).
String nfc(String s) => unorm.nfc(s);

/// Chave de comparação: NFC + minúsculas (ignora caixa, NÃO ignora acento) —
/// igual ao NTFS/APFS e ao `Nome::chave()` do servidor.
///
/// ⚠️ "İ" (U+0130): o `mb_strtolower` do PHP o leva a "i" + ponto combinante
/// (U+0307), e o `toLowerCase` do Dart a "i" puro. Igualado aqui, senão a
/// chave do aplicativo e a do servidor discordariam (o teste do contrato pega).
///
/// ⚠️ O sigma final grego também: "ΣΊΣΥΦΟΣ" vira "σίσυφος" no PHP (Σ no fim
/// da palavra → ς), e o Dart daria "σίσυφοσ".
String chaveNome(String nome) {
  final s = nfc(nome).replaceAll('\u0130', 'i\u0307');
  if (!s.contains('\u03A3')) return s.toLowerCase();
  final r = s.runes.toList();
  final letra = RegExp(r'\p{L}', unicode: true);
  final marca = RegExp(r'[\p{Mn}\p{Me}\p{Cf}\p{Lm}\p{Sk}\u0027\u00B7\u2019]', unicode: true);
  bool cased(int c) => letra.hasMatch(String.fromCharCode(c));
  bool ignoravel(int c) => marca.hasMatch(String.fromCharCode(c));
  final out = StringBuffer();
  for (var i = 0; i < r.length; i++) {
    if (r[i] != 0x03A3) {
      out.write(String.fromCharCode(r[i]).toLowerCase());
      continue;
    }
    var j = i - 1;
    while (j >= 0 && ignoravel(r[j])) {
      j--;
    }
    var k = i + 1;
    while (k < r.length && ignoravel(r[k])) {
      k++;
    }
    final finalSigma = j >= 0 && cased(r[j]) && !(k < r.length && cased(r[k]));
    out.write(finalSigma ? '\u03C2' : '\u03C3');
  }
  return out.toString();
}

/// Chave de um caminho relativo inteiro ("A/b/C.txt").
String chaveCaminho(String caminho) => caminho.split('/').map(chaveNome).join('/');

/// Motivo pelo qual o nome não serve, ou null se serve.
String? motivoNome(String nome) {
  if (nome.isEmpty) return 'o nome está vazio';
  final n = nfc(nome);
  if (n == '.' || n == '..') return 'o nome não pode ser "$n"';
  if (RegExp(r'[\x00-\x1F]').hasMatch(n)) return 'o nome tem um caractere de controle';
  for (final c in proibidos) {
    if (n.contains(c)) return 'o nome não pode ter ${proibidos.join(' ')} (tem "$c")';
  }
  if (n.endsWith('.') || n.endsWith(' ')) return 'o nome não pode terminar com ponto nem com espaço';
  if (_reservados.contains(_semExtensao(n))) return '"$n" é um nome reservado do Windows';
  if (utf8.encode(n).length > maxBytesNome) return 'o nome é longo demais (máximo de 255 bytes)';
  return null;
}

bool nomeValido(String nome) => motivoNome(nome) == null;

/// Extensão em minúsculas, sem ponto ('' se não houver).
String extensao(String nome) {
  final p = nome.lastIndexOf('.');
  if (p <= 0) return '';
  final e = nome.substring(p + 1).toLowerCase();
  return RegExp(r'^[a-z0-9]{1,20}$').hasMatch(e) ? e : '';
}

/// Nome da cópia de conflito, igual ao do servidor:
/// "Relatório (conflito de NOTEBOOK-ANA 2026-10-28 14h30).pdf"
String nomeConflito(String nome, String computador, DateTime quando) {
  var pc = computador.replaceAll(RegExp(r'[\x00-\x1F]'), '');
  for (final c in proibidos) {
    pc = pc.replaceAll(c, '_');
  }
  pc = pc.trim();
  if (pc.isEmpty) pc = 'outro computador';
  if (pc.length > 40) pc = pc.substring(0, 40);
  String d2(int n) => n.toString().padLeft(2, '0');
  final q = '${quando.year}-${d2(quando.month)}-${d2(quando.day)} ${d2(quando.hour)}h${d2(quando.minute)}';
  return _comTrecho(nome, ' (conflito de $pc $q)');
}

/// "nome (2).ext" — para quando o nome escolhido já existe.
String nomeComSufixo(String nome, int n) => _comTrecho(nome, ' ($n)');

String _comTrecho(String nome, String trecho) {
  final ext = extensao(nome);
  var base = ext.isNotEmpty ? nome.substring(0, nome.length - ext.length - 1) : nome;
  final fim = trecho + (ext.isNotEmpty ? '.$ext' : '');
  base = _cortarBytes(base, maxBytesNome - utf8.encode(fim).length).replaceAll(RegExp(r'[. ]+$'), '');
  return (base.isEmpty ? 'arquivo' : base) + fim;
}

String _cortarBytes(String s, int max) {
  if (utf8.encode(s).length <= max) return s;
  final runes = s.runes.toList();
  final out = StringBuffer();
  var n = 0;
  for (final r in runes) {
    final b = utf8.encode(String.fromCharCode(r)).length;
    if (n + b > max) break;
    out.writeCharCode(r);
    n += b;
  }
  return out.toString();
}

String _semExtensao(String nome) {
  final p = nome.indexOf('.');
  return (p < 0 ? nome : nome.substring(0, p)).trimRight().toLowerCase();
}
