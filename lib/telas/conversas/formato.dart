// A formatação das mensagens — a MESMA do chat do site (`App\Core\ChatHtml`):
// negrito, itálico, sublinhado e as 7 cores da paleta (`im-cor-0..6`), mais o
// realce das @menções (`im-mention`). Nada além disso: o servidor limpa tudo o
// que não estiver nesta lista, então o app nunca desenha HTML arbitrário.
//
//   partesDoHtml()          HTML permitido → trechos (para desenhar e para editar)
//   ControladorFormatado    o compositor: texto + o estilo de cada caractere
//   .paraHtml()             o compositor → HTML (enviado com `format=html`)
import 'package:flutter/material.dart';

/// As cores do chat, na ordem do servidor (`ChatHtml::CORES`). A 0 é a "padrão".
const coresChat = [
  Color(0xFF2B1F1F), Color(0xFFC0322F), Color(0xFFD97706), Color(0xFF12A150),
  Color(0xFF2563EB), Color(0xFF7C3AED), Color(0xFF6B7280),
];
const nomesCoresChat = ['Padrão', 'Vermelho', 'Laranja', 'Verde', 'Azul', 'Roxo', 'Cinza'];

/// A cor de texto no modo atual (no escuro, a "padrão" é a cor do texto e as
/// outras são clareadas para continuar legíveis sobre o fundo escuro).
Color corChat(int i, Brightness b, Color texto) {
  if (i <= 0 || i >= coresChat.length) return texto;
  final c = coresChat[i];
  return b == Brightness.dark ? Color.lerp(c, Colors.white, .38)! : c;
}

@immutable
class Estilo {
  final bool b, i, u;
  final int cor;   // 0 = padrão
  const Estilo({this.b = false, this.i = false, this.u = false, this.cor = 0});
  static const nada = Estilo();

  Estilo com({bool? b, bool? i, bool? u, int? cor}) => Estilo(b: b ?? this.b, i: i ?? this.i, u: u ?? this.u, cor: cor ?? this.cor);

  @override
  bool operator ==(Object other) => other is Estilo && other.b == b && other.i == i && other.u == u && other.cor == cor;
  @override
  int get hashCode => Object.hash(b, i, u, cor);
}

class Parte {
  final String texto;
  final Estilo estilo;
  final bool mencao;
  const Parte(this.texto, this.estilo, {this.mencao = false});
}

String _decodificar(String s) {
  return s.replaceAllMapped(RegExp(r'&(#x[0-9a-fA-F]+|#\d+|amp|lt|gt|quot|apos|nbsp|#39);'), (m) {
    final e = m.group(1)!;
    switch (e) {
      case 'amp':
        return '&';
      case 'lt':
        return '<';
      case 'gt':
        return '>';
      case 'quot':
        return '"';
      case 'apos':
      case '#39':
        return "'";
      case 'nbsp':
        return ' ';
    }
    final n = e.startsWith('#x') ? int.tryParse(e.substring(2), radix: 16) : int.tryParse(e.substring(1));
    return n == null ? m.group(0)! : String.fromCharCode(n);
  });
}

/// HTML do chat → trechos. Tag desconhecida é ignorada (o texto dela fica).
List<Parte> partesDoHtml(String html) {
  final out = <Parte>[];
  final pilha = <(String tag, Estilo antes, bool mencaoAntes)>[];
  var est = Estilo.nada;
  var mencao = false;
  for (final m in RegExp(r'<[^>]*>|[^<]+').allMatches(html)) {
    final t = m.group(0)!;
    if (!t.startsWith('<')) {
      final texto = _decodificar(t).replaceAll('​', '');
      if (texto.isNotEmpty) out.add(Parte(texto, est, mencao: mencao));
      continue;
    }
    final fecha = t.startsWith('</');
    final nome = RegExp(r'^</?\s*([a-zA-Z0-9]+)').firstMatch(t)?.group(1)?.toLowerCase() ?? '';
    if (nome == 'br') {
      out.add(Parte('\n', est, mencao: mencao));
      continue;
    }
    if (fecha) {
      final i = pilha.lastIndexWhere((x) => x.$1 == nome);
      if (i >= 0) {
        est = pilha[i].$2;
        mencao = pilha[i].$3;
        pilha.removeRange(i, pilha.length);
      }
      continue;
    }
    if (t.endsWith('/>')) continue;
    switch (nome) {
      case 'b':
      case 'strong':
        pilha.add((nome, est, mencao));
        est = est.com(b: true);
      case 'i':
      case 'em':
        pilha.add((nome, est, mencao));
        est = est.com(i: true);
      case 'u':
        pilha.add((nome, est, mencao));
        est = est.com(u: true);
      case 'span':
        pilha.add((nome, est, mencao));
        final cls = RegExp(r'''class\s*=\s*["']([^"']*)["']''').firstMatch(t)?.group(1) ?? '';
        final cor = RegExp(r'im-cor-(\d)').firstMatch(cls);
        if (cor != null) est = est.com(cor: int.parse(cor.group(1)!));
        if (cls.contains('im-mention')) mencao = true;
      default:
        // tag fora da lista: o servidor já a teria removido; aqui só é ignorada
        break;
    }
  }
  return out;
}

String _escapar(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

/// O compositor: um campo de texto comum que guarda o ESTILO de cada caractere.
class ControladorFormatado extends TextEditingController {
  List<Estilo> _estilos = [];
  Estilo _pendente = Estilo.nada;
  bool _temPendente = false;
  Brightness brilho = Brightness.light;
  Color corTexto = const Color(0xFF2B1F1F);

  List<Estilo> get estilos => List.unmodifiable(_estilos);

  @override
  set value(TextEditingValue novo) {
    final antes = super.value.text;
    final depois = novo.text;
    if (antes == depois) {
      // Só o cursor andou: o estilo "pendente" (escolhido sem seleção) acaba.
      if (novo.selection != super.value.selection) _temPendente = false;
      super.value = novo;
      return;
    }
    var pre = 0;
    final minimo = antes.length < depois.length ? antes.length : depois.length;
    while (pre < minimo && antes.codeUnitAt(pre) == depois.codeUnitAt(pre)) {
      pre++;
    }
    var suf = 0;
    while (suf < minimo - pre && antes.codeUnitAt(antes.length - 1 - suf) == depois.codeUnitAt(depois.length - 1 - suf)) {
      suf++;
    }
    final inseridos = depois.length - pre - suf;
    final e = _temPendente ? _pendente : (pre > 0 && pre - 1 < _estilos.length ? _estilos[pre - 1] : (_estilos.isNotEmpty ? _estilos.first : Estilo.nada));
    final base = _estilos.length == antes.length ? _estilos : List<Estilo>.filled(antes.length, Estilo.nada);
    _estilos = [
      ...base.sublist(0, pre),
      ...List<Estilo>.filled(inseridos < 0 ? 0 : inseridos, e),
      ...base.sublist(antes.length - suf),
    ];
    super.value = novo;
  }

  /// Estilo no cursor (para acender os botões da barra).
  Estilo get atual {
    if (_temPendente) return _pendente;
    final s = selection;
    if (!s.isValid || _estilos.isEmpty) return Estilo.nada;
    final i = (s.isCollapsed ? s.start - 1 : s.start).clamp(0, _estilos.length - 1);
    return _estilos[i];
  }

  void _aplicar(Estilo Function(Estilo e, bool ligar) f, bool Function(Estilo e) tem) {
    final s = selection;
    if (s.isValid && !s.isCollapsed) {
      final ini = s.start.clamp(0, _estilos.length), fim = s.end.clamp(0, _estilos.length);
      final todos = _estilos.sublist(ini, fim).every(tem);
      for (var k = ini; k < fim; k++) {
        _estilos[k] = f(_estilos[k], !todos);
      }
    } else {
      final e = atual;
      _pendente = f(e, !tem(e));
      _temPendente = true;
    }
    notifyListeners();
  }

  void alternarNegrito() => _aplicar((e, l) => e.com(b: l), (e) => e.b);
  void alternarItalico() => _aplicar((e, l) => e.com(i: l), (e) => e.i);
  void alternarSublinhado() => _aplicar((e, l) => e.com(u: l), (e) => e.u);
  void definirCor(int cor) => _aplicar((e, _) => e.com(cor: cor), (_) => false);

  /// Insere texto no cursor (emoji, menção, colagem), com o estilo do lugar.
  void inserir(String t) {
    final s = selection.isValid ? selection : TextSelection.collapsed(offset: text.length);
    final novo = text.replaceRange(s.start, s.end, t);
    value = TextEditingValue(text: novo, selection: TextSelection.collapsed(offset: s.start + t.length));
  }

  bool get vazio => text.trim().isEmpty;

  /// Tem alguma formatação? (sem nenhuma, a mensagem vai como texto puro)
  bool get formatado => _estilos.any((e) => e != Estilo.nada);

  String paraHtml() {
    final out = StringBuffer();
    var k = 0;
    while (k < text.length) {
      final e = k < _estilos.length ? _estilos[k] : Estilo.nada;
      var j = k;
      while (j < text.length && (j < _estilos.length ? _estilos[j] : Estilo.nada) == e) {
        j++;
      }
      final pedaco = _escapar(text.substring(k, j)).replaceAll('\n', '<br>');
      var abre = '', fecha = '';
      if (e.cor > 0) {
        abre += '<span class="im-cor-${e.cor}">';
        fecha = '</span>$fecha';
      }
      if (e.b) {
        abre += '<b>';
        fecha = '</b>$fecha';
      }
      if (e.i) {
        abre += '<i>';
        fecha = '</i>$fecha';
      }
      if (e.u) {
        abre += '<u>';
        fecha = '</u>$fecha';
      }
      out.write('$abre$pedaco$fecha');
      k = j;
    }
    return out.toString();
  }

  /// Carrega uma mensagem para editar (HTML do chat ou texto puro).
  void carregar(String corpo, {bool html = false}) {
    if (!html) {
      _estilos = List<Estilo>.filled(corpo.length, Estilo.nada);
      super.value = TextEditingValue(text: corpo, selection: TextSelection.collapsed(offset: corpo.length));
      return;
    }
    final partes = partesDoHtml(corpo);
    final t = StringBuffer();
    final est = <Estilo>[];
    for (final p in partes) {
      t.write(p.texto);
      est.addAll(List<Estilo>.filled(p.texto.length, p.estilo));
    }
    _estilos = est;
    super.value = TextEditingValue(text: t.toString(), selection: TextSelection.collapsed(offset: t.length));
  }

  void limpar() {
    _estilos = [];
    _temPendente = false;
    super.value = TextEditingValue.empty;
  }

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    final filhos = <TextSpan>[];
    var k = 0;
    while (k < text.length) {
      final e = k < _estilos.length ? _estilos[k] : Estilo.nada;
      var j = k;
      while (j < text.length && (j < _estilos.length ? _estilos[j] : Estilo.nada) == e) {
        j++;
      }
      filhos.add(TextSpan(
        text: text.substring(k, j),
        style: TextStyle(
          fontWeight: e.b ? FontWeight.w700 : null,
          fontStyle: e.i ? FontStyle.italic : null,
          decoration: e.u ? TextDecoration.underline : null,
          color: e.cor > 0 ? corChat(e.cor, brilho, corTexto) : null,
        ),
      ));
      k = j;
    }
    return TextSpan(style: style, children: filhos);
  }
}
