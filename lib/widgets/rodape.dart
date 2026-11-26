// O rodapé igual ao do NN Conecta (layouts/authenticated): o texto da marca à
// esquerda — aqui com a versão do app junto —, o "Canal de denúncia" e a "LGPD".
//
// Os endereços vêm do servidor (`aparencia.rodape`): o canal e a página da LGPD
// abrem no NAVEGADOR, nunca dentro do app — é lá que o canal garante o
// anonimato (o app manda o token e a identificação do computador em toda
// chamada; o navegador, não).
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../tema.dart';

/// A cor do texto do rodapé do site (`.app-footer { color: #98a2b3 }`), a mesma
/// nos dois modos.
const _corRodape = Color(0xFF98A2B3);

class RodapeApp extends StatelessWidget {
  /// A resposta de `GET /v1/callapp/aparencia` (pode ser nula antes de carregar).
  final Map<String, dynamic>? aparencia;
  const RodapeApp(this.aparencia, {super.key});

  /// O que o rodapé mostra, a partir da aparência. Separado do desenho para
  /// ser testado sem montar a tela.
  static ({String texto, String? denuncia, String? lgpd}) dados(Map<String, dynamic>? a, {int? ano}) {
    final site = (a?['site_url'] ?? '').toString().replaceAll(RegExp(r'/+$'), '');
    final r = a?['rodape'] is Map ? (a!['rodape'] as Map) : null;
    String marca = (r?['texto'] ?? '').toString().trim();
    if (marca.isEmpty) {
      final sistema = (a?['sistema'] ?? 'Conecta').toString();
      final empresa = (a?['empresa'] ?? '').toString();
      marca = empresa.isEmpty || empresa == sistema ? sistema : '$sistema · $empresa';
    }
    String? link(String chave, String caminho) {
      // Servidor novo diz o endereço (nulo = não mostrar); o antigo não manda o
      // bloco, e aí vale o caminho do site.
      if (r != null) {
        final v = (r[chave] ?? '').toString();
        return v.startsWith('https://') || (AppConfig.modoTeste && v.startsWith('http://')) ? v : null;
      }
      return site.isEmpty ? null : '$site$caminho';
    }

    return (
      texto: '© ${ano ?? DateTime.now().year} $marca',
      denuncia: link('denuncia', '/denuncia'),
      lgpd: link('lgpd', '/lgpd'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final d = dados(aparencia);
    const estilo = TextStyle(color: _corRodape, fontSize: 12.8, height: 1.35);
    final esquerda = Text.rich(
      TextSpan(children: [
        TextSpan(text: d.texto),
        const TextSpan(text: '  ·  '),
        TextSpan(text: '${AppConfig.nome} ${AppConfig.versao}', style: const TextStyle(fontWeight: FontWeight.w600)),
      ]),
      style: estilo,
    );
    return DefaultTextStyle.merge(
      style: estilo,
      child: Container(
        width: double.infinity,
        color: p.bg,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 16,
          runSpacing: 6,
          children: [
            esquerda,
            if (d.denuncia != null)
              _LinkRodape(rotulo: 'Canal de denúncia', icone: Icons.gpp_maybe_outlined, corIcone: p.danger, url: d.denuncia!),
            if (d.lgpd != null) _LinkRodape(rotulo: 'LGPD', icone: Icons.lock_outline_rounded, corIcone: p.primary, url: d.lgpd!),
          ],
        ),
      ),
    );
  }
}

class _LinkRodape extends StatefulWidget {
  final String rotulo, url;
  final IconData icone;
  final Color corIcone;
  const _LinkRodape({required this.rotulo, required this.icone, required this.corIcone, required this.url});

  @override
  State<_LinkRodape> createState() => _LinkRodapeState();
}

class _LinkRodapeState extends State<_LinkRodape> {
  bool _sobre = false;

  @override
  Widget build(BuildContext context) {
    final cor = _sobre ? context.pal.primary : _corRodape;
    // InkWell e não GestureDetector: recebe foco pelo Tab e abre com Enter.
    return Semantics(
      link: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        hoverColor: Colors.transparent,
        onHover: (v) => setState(() => _sobre = v),
        onTap: () => launchUrl(Uri.parse(widget.url), mode: LaunchMode.externalApplication),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(widget.icone, size: 16, color: widget.corIcone),
            const SizedBox(width: 6),
            Text(widget.rotulo,
                style: TextStyle(
                    color: cor,
                    fontSize: 12.8,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.underline,
                    decorationColor: cor)),
          ]),
        ),
      ),
    );
  }
}

/// A linha do canal na tela de entrada (como o `auth-den` do login do site):
/// quem ainda não entrou — ou nem quer entrar — também precisa achar o canal.
class LinhaDenuncia extends StatelessWidget {
  final Map<String, dynamic>? aparencia;
  const LinhaDenuncia(this.aparencia, {super.key});

  @override
  Widget build(BuildContext context) {
    final url = RodapeApp.dados(aparencia).denuncia;
    if (url == null) return const SizedBox.shrink();
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _LinkRodape(rotulo: 'Canal de denúncia', icone: Icons.gpp_maybe_outlined, corIcone: context.pal.danger, url: url),
        Text(' · relate uma irregularidade ao Jurídico, com ou sem identificação.',
            style: TextStyle(color: context.pal.muted, fontSize: 12.5)),
      ],
    );
  }
}
