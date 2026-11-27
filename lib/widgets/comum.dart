// Peças comuns das telas: imagem da API (com o token), avatar, cartão
// com título, estado vazio e texto com links.
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/cliente.dart';
import '../tema.dart';

/// Imagem servida pela API do app (anexo do chat, mídia do NN News): o endereço
/// exige o token da sessão, então não dá para usar `Image.network`.
/// Guarda as últimas em memória para a lista não baixar de novo a cada rolagem.
class ImagemApi extends StatefulWidget {
  final Api api;
  final String caminho;
  final BoxFit fit;
  final double? largura, altura;
  final Widget? reserva;
  const ImagemApi(this.api, this.caminho, {super.key, this.fit = BoxFit.cover, this.largura, this.altura, this.reserva});

  static final _cache = <String, Uint8List>{};
  static const _max = 160;

  static Future<Uint8List> carregar(Api api, String caminho) async {
    final c = _cache.remove(caminho);
    if (c != null) {
      _cache[caminho] = c;
      return c;
    }
    final b = Uint8List.fromList(await api.bytes(caminho));
    _cache[caminho] = b;
    while (_cache.length > _max) {
      _cache.remove(_cache.keys.first);
    }
    return b;
  }

  @override
  State<ImagemApi> createState() => _ImagemApiState();
}

class _ImagemApiState extends State<ImagemApi> {
  Future<Uint8List>? _f;

  @override
  void initState() {
    super.initState();
    _f = ImagemApi.carregar(widget.api, widget.caminho);
  }

  @override
  void didUpdateWidget(covariant ImagemApi old) {
    super.didUpdateWidget(old);
    if (old.caminho != widget.caminho) _f = ImagemApi.carregar(widget.api, widget.caminho);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _f,
      builder: (_, s) {
        if (s.hasData) {
          return Image.memory(s.data!, fit: widget.fit, width: widget.largura, height: widget.altura, gaplessPlayback: true,
              errorBuilder: (_, __, ___) => _reserva(context));
        }
        if (s.hasError) return _reserva(context);
        return Container(width: widget.largura, height: widget.altura, color: context.pal.surface);
      },
    );
  }

  Widget _reserva(BuildContext context) =>
      widget.reserva ??
      Container(
        width: widget.largura,
        height: widget.altura,
        color: context.pal.surface,
        alignment: Alignment.center,
        child: Icon(Icons.broken_image_outlined, color: context.pal.muted),
      );
}

/// Foto de perfil (endereço público do site) ou a inicial.
class Avatar extends StatelessWidget {
  final String? url;
  final String nome;
  final double tam;
  final Widget? ponto;
  const Avatar({super.key, this.url, required this.nome, this.tam = 36, this.ponto});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final inicial = nome.trim().isEmpty ? '?' : nome.trim().characters.first.toUpperCase();
    final base = ClipOval(
      child: SizedBox(
        width: tam,
        height: tam,
        child: (url ?? '').isNotEmpty
            ? Image.network(url!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _letra(p, inicial))
            : _letra(p, inicial),
      ),
    );
    if (ponto == null) return base;
    return SizedBox(
      width: tam,
      height: tam,
      child: Stack(clipBehavior: Clip.none, children: [base, Positioned(right: -1, bottom: -1, child: ponto!)]),
    );
  }

  Widget _letra(Paleta p, String l) => Container(
        color: p.primary.withValues(alpha: .14),
        alignment: Alignment.center,
        child: Text(l, style: TextStyle(color: p.primary, fontWeight: FontWeight.w700, fontSize: tam * .42)),
      );
}

/// O cartão das telas: título + ação à direita + conteúdo.
class CartaoSecao extends StatelessWidget {
  final String titulo;
  final IconData? icone;
  final Widget? acao;
  final Widget child;
  final EdgeInsets padding;
  const CartaoSecao({super.key, required this.titulo, this.icone, this.acao, required this.child, this.padding = const EdgeInsets.fromLTRB(18, 14, 18, 18)});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Card(
      child: Padding(
        padding: padding,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            if (icone != null) ...[Icon(icone, size: 20, color: p.primary), const SizedBox(width: 8)],
            Expanded(child: Text(titulo, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
            if (acao != null) acao!,
          ]),
          const SizedBox(height: 12),
          child,
        ]),
      ),
    );
  }
}

class Vazio extends StatelessWidget {
  final IconData icone;
  final String texto;
  const Vazio(this.icone, this.texto, {super.key});
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 26),
      child: Column(children: [
        Icon(icone, size: 34, color: p.muted),
        const SizedBox(height: 8),
        Text(texto, textAlign: TextAlign.center, style: TextStyle(color: p.muted)),
      ]),
    );
  }
}

/// Texto com os endereços http(s) virando links (abrem no navegador, com aviso).
class TextoComLinks extends StatefulWidget {
  final String texto;
  final TextStyle? estilo;
  const TextoComLinks(this.texto, {super.key, this.estilo});
  @override
  State<TextoComLinks> createState() => _TextoComLinksState();
}

class _TextoComLinksState extends State<TextoComLinks> {
  final List<TapGestureRecognizer> _toques = [];

  @override
  void dispose() {
    for (final t in _toques) {
      t.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    for (final t in _toques) {
      t.dispose();
    }
    _toques.clear();
    final spans = <InlineSpan>[];
    final re = RegExp(r'(https?://[^\s<>"]+|www\.[^\s<>"]+)', caseSensitive: false);
    var i = 0;
    for (final m in re.allMatches(widget.texto)) {
      var url = m.group(0)!;
      var resto = '';
      while (url.isNotEmpty && '.,;:!?)'.contains(url[url.length - 1])) {
        resto = url[url.length - 1] + resto;
        url = url.substring(0, url.length - 1);
      }
      spans.add(TextSpan(text: widget.texto.substring(i, m.start)));
      final t = TapGestureRecognizer()..onTap = () => abrirLink(context, url);
      _toques.add(t);
      spans.add(TextSpan(text: url, style: TextStyle(color: context.pal.primary, decoration: TextDecoration.underline), recognizer: t));
      spans.add(TextSpan(text: resto));
      i = m.end;
    }
    spans.add(TextSpan(text: widget.texto.substring(i)));
    return SelectableText.rich(TextSpan(style: widget.estilo ?? DefaultTextStyle.of(context).style, children: spans));
  }
}

/// Abre um endereço externo no navegador, depois de mostrar o destino por extenso
/// (o aviso de saída do chat do site). Só http(s).
Future<void> abrirLink(BuildContext context, String url) async {
  var u = url.trim();
  if (u.toLowerCase().startsWith('www.')) u = 'https://$u';
  final uri = Uri.tryParse(u);
  if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) return;
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: const Text('Abrir link externo?'),
      content: SelectableText(u),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Abrir no navegador')),
      ],
    ),
  );
  if (ok == true) await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// "26 de novembro" / "hoje, 14:05" a partir de "Y-m-d H:i:s".
String dataCurta(String? iso) {
  final d = DateTime.tryParse((iso ?? '').replaceFirst(' ', 'T'));
  if (d == null) return '';
  final agora = DateTime.now();
  final hm = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  final hoje = DateTime(agora.year, agora.month, agora.day);
  final dia = DateTime(d.year, d.month, d.day);
  final dif = hoje.difference(dia).inDays;
  if (dif == 0) return 'hoje, $hm';
  if (dif == 1) return 'ontem, $hm';
  const meses = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];
  return '${d.day} ${meses[d.month - 1]}${d.year != agora.year ? ' ${d.year}' : ''}';
}

/// Mensagem de erro rápida na base da tela.
void avisar(BuildContext context, String texto, {bool erro = false}) {
  final m = ScaffoldMessenger.maybeOf(context);
  m?.hideCurrentSnackBar();
  m?.showSnackBar(SnackBar(
    content: Text(texto),
    backgroundColor: erro ? context.pal.danger : null,
    behavior: SnackBarBehavior.floating,
    width: 520,
  ));
}

String erroDe(Object e) => e is ApiErro ? e.mensagem : 'Algo deu errado. Tente de novo.';
