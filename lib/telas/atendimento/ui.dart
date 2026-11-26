// Peças visuais do Atendimento — as mesmas do portal (`.cb-*` do app.css): as
// tintas de alerta por modo, as pílulas de situação, os títulos de seção e os
// campos de formulário.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../tema.dart';
import '../../widgets/comum.dart';

/// Os tons do portal: `ok` (sucesso), `perigo` (erro), `info`, `alerta`, `neutro`.
/// As tintas são as `--alert-*-ink` do app.css, uma por modo (o fundo é a
/// própria cor translúcida, como lá).
Color tinta(BuildContext context, String tom) {
  final escuro = Theme.of(context).brightness == Brightness.dark;
  return switch (tom) {
    'ok' ||
    'positivo' =>
      escuro ? const Color(0xFF6CD996) : const Color(0xFF087443),
    'perigo' ||
    'negativo' =>
      escuro ? const Color(0xFFF2938D) : const Color(0xFFB42318),
    'info' ||
    'neutro_info' =>
      escuro ? const Color(0xFF9DBDFF) : const Color(0xFF1D4ED8),
    'alerta' => escuro ? const Color(0xFFF0B357) : const Color(0xFF92400E),
    _ => context.pal.muted,
  };
}

Color fundoTom(BuildContext context, String tom) => switch (tom) {
      'ok' || 'positivo' => const Color(0xFF10B981).withValues(alpha: .14),
      'perigo' || 'negativo' => const Color(0xFFDC2626).withValues(alpha: .12),
      'info' || 'neutro_info' => const Color(0xFF2563EB).withValues(alpha: .12),
      'alerta' => const Color(0xFFF59E0B).withValues(alpha: .16),
      _ => context.pal.surface,
    };

/// A classe de um acionamento (positivo · negativo · neutro) → tom.
String tomDaClasse(String classe) => switch (classe) {
      'positivo' => 'ok',
      'negativo' => 'perigo',
      _ => 'info',
    };

IconData iconeDaClasse(String classe) => switch (classe) {
      'positivo' => Icons.thumb_up_alt_outlined,
      'negativo' => Icons.thumb_down_alt_outlined,
      _ => Icons.info_outline_rounded,
    };

/// Pílula de situação (`.cb-tel-st`, `.cb-ag-st`…).
class Pilula extends StatelessWidget {
  final String texto;
  final String tom;
  const Pilula(this.texto, {super.key, this.tom = 'neutro'});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
            color: fundoTom(context, tom),
            borderRadius: BorderRadius.circular(999)),
        child: Text(texto,
            style: TextStyle(
                color: tinta(context, tom),
                fontSize: 11.5,
                fontWeight: FontWeight.w600)),
      );
}

/// Marca pequena (`.cb-tag`): "você", "automático", "enviado"…
class Etiqueta extends StatelessWidget {
  final String texto;
  const Etiqueta(this.texto, {super.key});
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
            color: context.pal.surface,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: context.pal.cardBorder)),
        child: Text(texto,
            style: TextStyle(
                fontSize: 11,
                color: context.pal.muted,
                fontWeight: FontWeight.w600)),
      );
}

/// Título de seção dentro de uma aba (`.cb-h2`).
class TituloSecao extends StatelessWidget {
  final String texto;
  final Widget? acao;
  const TituloSecao(this.texto, {super.key, this.acao});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 10),
        child: Row(children: [
          Expanded(
              child: Text(texto,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700))),
          if (acao != null) acao!,
        ]),
      );
}

/// Faixa de aviso (`.alert-info`, `.alert-error`…).
class Alerta extends StatelessWidget {
  final Widget child;
  final String tom;
  const Alerta(this.child, {super.key, this.tom = 'info'});
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: fundoTom(context, tom),
            borderRadius: BorderRadius.circular(10)),
        child: DefaultTextStyle.merge(
            style: TextStyle(color: tinta(context, tom), fontSize: 13.5),
            child: child),
      );
}

/// Estado vazio de uma lista (`.cb-lt-vazio`).
class CaixaVazia extends StatelessWidget {
  final String texto;
  const CaixaVazia(this.texto, {super.key});
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
        decoration: BoxDecoration(
            color: context.pal.surface,
            borderRadius: BorderRadius.circular(10)),
        child: Text(texto,
            textAlign: TextAlign.center,
            style: TextStyle(color: context.pal.muted)),
      );
}

/// Rótulo + campo, como o `.ff` do portal.
class CampoForm extends StatelessWidget {
  final String rotulo;
  final Widget child;
  final String? dica;
  const CampoForm(this.rotulo, this.child, {super.key, this.dica});
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(rotulo,
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: context.pal.muted)),
        const SizedBox(height: 5),
        child,
        if (dica != null) ...[
          const SizedBox(height: 4),
          Text(dica!, style: TextStyle(fontSize: 12, color: context.pal.muted)),
        ],
      ]);
}

/// Uma linha de campos com proporções (o `.form-grid` de 12 colunas).
class LinhaForm extends StatelessWidget {
  final List<(int, Widget)> campos;
  const LinhaForm(this.campos, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var i = 0; i < campos.length; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            Expanded(flex: campos[i].$1, child: campos[i].$2),
          ],
        ]),
      );
}

/// Botão "Copiar" pequeno (`.cb-copiar`).
class BotaoCopiar extends StatelessWidget {
  final String texto;
  final String rotulo;
  const BotaoCopiar(this.texto, {super.key, this.rotulo = 'Copiar'});
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 26,
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              // Do tema (senão o texto perde a família da fonte do app).
              textStyle: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(fontSize: 11.5, fontWeight: FontWeight.w600)),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: texto));
            avisar(context, 'Copiado.');
          },
          child: Text(rotulo),
        ),
      );
}

/// Texto que vira link discreto (`<a>` do portal).
class LinkTexto extends StatelessWidget {
  final String texto;
  final VoidCallback onTap;
  final double tam;
  final bool sublinhado;
  const LinkTexto(this.texto, this.onTap,
      {super.key, this.tam = 13.5, this.sublinhado = true});
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(3),
        child: Text(texto,
            style: TextStyle(
                color: context.pal.primary,
                fontSize: tam,
                fontWeight: sublinhado ? FontWeight.w600 : FontWeight.w700,
                decoration: sublinhado ? TextDecoration.underline : null,
                decorationColor: context.pal.primary)),
      );
}

/// Pergunta antes de uma ação (o `data-confirm` do portal).
Future<bool> confirmarAcao(BuildContext context, String pergunta,
    {String sim = 'Confirmar'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      content: Text(pergunta),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true), child: Text(sim)),
      ],
    ),
  );
  return r == true;
}

/// "2026-11-26" ↔ "26/11/2026".
String dataBr(String iso) {
  final p = iso.split('-');
  return p.length == 3 ? '${p[2]}/${p[1]}/${p[0]}' : iso;
}

String dataIso(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Campo de data que abre o calendário (o `<input type=date>` do portal).
class CampoData extends StatelessWidget {
  final String valor; // AAAA-MM-DD ou vazio
  final ValueChanged<String> aoMudar;
  final DateTime? minimo;
  final String vazio;
  const CampoData(
      {super.key,
      required this.valor,
      required this.aoMudar,
      this.minimo,
      this.vazio = 'Escolher a data'});
  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () async {
          final atual = DateTime.tryParse(valor) ?? DateTime.now();
          final inicio = minimo ?? DateTime(2000);
          final d = await showDatePicker(
            context: context,
            initialDate: atual.isBefore(inicio) ? inicio : atual,
            firstDate: inicio,
            lastDate: DateTime.now().add(const Duration(days: 3650)),
            locale: const Locale('pt', 'BR'),
          );
          if (d != null) aoMudar(dataIso(d));
        },
        child: InputDecorator(
          decoration: const InputDecoration(
              suffixIcon: Icon(Icons.calendar_today_outlined, size: 18)),
          child: Text(valor.isEmpty ? vazio : dataBr(valor),
              style:
                  TextStyle(color: valor.isEmpty ? context.pal.muted : null)),
        ),
      );
}

/// Grava um documento em Downloads (nome sem repetir) e o abre no programa padrão.
Future<void> salvarEAbrir(BuildContext context, String nome,
    Future<File> Function(File destino) baixar) async {
  try {
    final pasta =
        await getDownloadsDirectory() ?? await getTemporaryDirectory();
    final limpo = nome.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    var destino = File('${pasta.path}/$limpo');
    var n = 2;
    while (destino.existsSync()) {
      final i = limpo.lastIndexOf('.');
      destino = File(
          '${pasta.path}/${i > 0 ? '${limpo.substring(0, i)} ($n)${limpo.substring(i)}' : '$limpo ($n)'}');
      n++;
    }
    final f = await baixar(destino);
    if (context.mounted) avisar(context, 'Salvo em ${f.path}');
    await launchUrl(Uri.file(f.path));
  } catch (e) {
    if (context.mounted) avisar(context, erroDe(e), erro: true);
  }
}

/// Cartão com a faixa colorida de um lado (`.cb-res`, `.cb-prop`, `.cb-aging-item`).
///
/// ⚠️ A faixa é um FILHO, nunca uma borda: o Flutter recusa em execução borda com
/// cores diferentes junto de `borderRadius` ("A borderRadius can only be given on
/// borders with uniform colors") — a mesma armadilha já registrada no app do celular.
class CartaoFaixa extends StatelessWidget {
  final Color cor;
  final Widget child;
  final EdgeInsets padding;
  final bool topo; // faixa em cima (senão, à esquerda)
  final double largura;
  final Color? fundo;
  final bool comBorda;
  final double raio;
  const CartaoFaixa({
    super.key,
    required this.cor,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.topo = false,
    this.largura = 4,
    this.fundo,
    this.comBorda = true,
    this.raio = 12,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final faixa = topo
        ? Container(height: largura, color: cor)
        : Container(width: largura, color: cor);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: fundo ?? p.card,
        borderRadius: BorderRadius.circular(raio),
        border: comBorda ? Border.all(color: p.cardBorder) : null,
      ),
      child: topo
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [faixa, Padding(padding: padding, child: child)])
          : IntrinsicHeight(
              child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    faixa,
                    Expanded(child: Padding(padding: padding, child: child))
                  ]),
            ),
    );
  }
}
