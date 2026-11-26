// O corpo das matérias do NN News e dos avisos (HTML já sanitizado no servidor).
// As imagens internas do NN News chegam como `nn-news-midia:<chave>` e são
// buscadas na API com o token; as de `/uploads/` são públicas.
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

import '../api/cliente.dart';
import '../tema.dart';
import 'comum.dart';

const esquemaMidiaNews = 'nn-news-midia:';

String midiaNews(String chave, {bool mini = false}) => '/v1/callapp/news/midia?m=${Uri.encodeQueryComponent(chave)}${mini ? '&t=mini' : ''}';

class HtmlConteudo extends StatelessWidget {
  final Api api;
  final String html;
  final double tamanho;
  const HtmlConteudo(this.api, this.html, {super.key, this.tamanho = 15.5});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return HtmlWidget(
      html,
      textStyle: TextStyle(fontSize: tamanho, height: 1.6, color: p.text),
      onTapUrl: (url) async {
        await abrirLink(context, url);
        return true;
      },
      customStylesBuilder: (e) {
        switch (e.localName) {
          case 'a':
            return {'color': _css(p.primary)};
          case 'blockquote':
            return {'border-left': '3px solid ${_css(p.primary)}', 'padding-left': '12px', 'color': _css(p.muted)};
          case 'table':
            return {'border-collapse': 'collapse'};
          case 'td':
          case 'th':
            return {'border': '1px solid ${_css(p.cardBorder)}', 'padding': '6px 8px'};
        }
        final cls = e.classes;
        if (cls.contains('ct-al-center')) return {'text-align': 'center'};
        if (cls.contains('ct-al-right')) return {'text-align': 'right'};
        if (cls.contains('ct-al-justify')) return {'text-align': 'justify'};
        return null;
      },
      customWidgetBuilder: (e) {
        if (e.localName == 'img') {
          final src = (e.attributes['src'] ?? '').trim();
          if (src.startsWith(esquemaMidiaNews)) {
            final k = src.substring(esquemaMidiaNews.length);
            if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(k)) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: ClipRRect(borderRadius: BorderRadius.circular(10), child: ImagemApi(api, midiaNews(k), fit: BoxFit.contain)),
            );
          }
          if (!src.startsWith('https://') && !src.startsWith('http://')) return const SizedBox.shrink();
        }
        if (e.localName == 'video' || e.localName == 'iframe' || e.localName == 'audio') {
          return Text('[mídia disponível no NN Conecta]', style: TextStyle(color: p.muted));
        }
        return null;
      },
    );
  }

  static String _css(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
}
