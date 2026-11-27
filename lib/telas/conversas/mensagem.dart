// A bolha da mensagem: texto formatado (as tags que o site permite), menções,
// links com o aviso de saída, citação, anexos (miniatura → visualizador, áudio
// tocando na bolha, arquivo para baixar e abrir), enquete, reunião do Meet, reações, "editada",
// "Encaminhada" e os tiques (enviada · entregue · lida).
import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/cliente.dart';
import '../../tema.dart';
import '../../widgets/comum.dart';
import 'chat_api.dart';
import 'emoji.dart';
import 'formato.dart';

/// As ações da bolha, ligadas pela conversa.
class AcoesMensagem {
  final void Function(Mensagem m) responder;
  final void Function(Mensagem m, String emoji) reagir;
  final void Function(Mensagem m) editar;
  final void Function(Mensagem m) encaminhar;
  final void Function(Mensagem m) quemLeu;
  final void Function(int id) irPara;
  final void Function(Mensagem m, OpcaoEnquete o) votar;
  final void Function(Mensagem m) encerrarEnquete;
  final void Function(Mensagem m) quemVotou;
  final void Function(Mensagem m) cancelarReuniao;
  const AcoesMensagem({
    required this.responder,
    required this.reagir,
    required this.editar,
    required this.encaminhar,
    required this.quemLeu,
    required this.irPara,
    required this.votar,
    required this.encerrarEnquete,
    required this.quemVotou,
    required this.cancelarReuniao,
  });
}

class BolhaMensagem extends StatefulWidget {
  final Api api;
  final Mensagem m;
  final bool grupo, souAdmin;
  final int meuId;
  final int tique; // 0 enviada · 1 entregue · 2 lida (só nas minhas)
  final String busca;
  final bool destacada;
  final bool selecionando, selecionada;
  final VoidCallback? alternarSelecao;
  final AcoesMensagem acoes;
  const BolhaMensagem({
    super.key,
    required this.api,
    required this.m,
    required this.grupo,
    required this.souAdmin,
    required this.meuId,
    required this.tique,
    required this.acoes,
    this.busca = '',
    this.destacada = false,
    this.selecionando = false,
    this.selecionada = false,
    this.alternarSelecao,
  });

  @override
  State<BolhaMensagem> createState() => _BolhaMensagemState();
}

class _BolhaMensagemState extends State<BolhaMensagem> {
  bool _sobre = false;
  Mensagem get m => widget.m;

  Future<void> _menu(Offset pos) async {
    final itens = <PopupMenuEntry<String>>[
      const PopupMenuItem(value: 'responder', child: ListTile(dense: true, leading: Icon(Icons.reply_rounded), title: Text('Responder'))),
      const PopupMenuItem(value: 'reagir', child: ListTile(dense: true, leading: Icon(Icons.add_reaction_outlined), title: Text('Reagir'))),
      if (m.corpo.trim().isNotEmpty && m.enquete == null)
        const PopupMenuItem(value: 'copiar', child: ListTile(dense: true, leading: Icon(Icons.copy_rounded), title: Text('Copiar texto'))),
      if (m.aindaEditavel && m.corpo.trim().isNotEmpty)
        const PopupMenuItem(value: 'editar', child: ListTile(dense: true, leading: Icon(Icons.edit_outlined), title: Text('Editar'))),
      if (m.enquete == null)
        const PopupMenuItem(value: 'encaminhar', child: ListTile(dense: true, leading: Icon(Icons.forward_rounded), title: Text('Encaminhar'))),
      if (m.minha && widget.grupo)
        const PopupMenuItem(value: 'quem_leu', child: ListTile(dense: true, leading: Icon(Icons.done_all_rounded), title: Text('Quem leu'))),
    ];
    final r = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx + 1, pos.dy + 1),
      items: itens,
    );
    if (!mounted || r == null) return;
    switch (r) {
      case 'responder':
        widget.acoes.responder(m);
      case 'reagir':
        final e = await escolherReacao(context);
        if (e != null) widget.acoes.reagir(m, e);
      case 'copiar':
        await Clipboard.setData(ClipboardData(text: m.corpo));
        if (mounted) avisar(context, 'Texto copiado.');
      case 'editar':
        widget.acoes.editar(m);
      case 'encaminhar':
        widget.acoes.encaminhar(m);
      case 'quem_leu':
        widget.acoes.quemLeu(m);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final escuro = Theme.of(context).brightness == Brightness.dark;
    final minha = m.minha;
    final fundo = minha
        ? Color.alphaBlend(pal.primary.withValues(alpha: escuro ? .26 : .11), pal.card)
        : pal.card;
    final bolha = Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      decoration: BoxDecoration(
        color: fundo,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(14),
          topRight: const Radius.circular(14),
          bottomLeft: Radius.circular(minha ? 14 : 4),
          bottomRight: Radius.circular(minha ? 4 : 14),
        ),
        border: Border.all(color: m.mencionaMim ? pal.primary : pal.cardBorder, width: m.mencionaMim ? 1.5 : 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        if (m.encaminhada)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.forward_rounded, size: 14, color: pal.muted),
              const SizedBox(width: 4),
              Text('Encaminhada', style: TextStyle(color: pal.muted, fontSize: 12, fontStyle: FontStyle.italic)),
            ]),
          ),
        if (m.resposta != null) _Citacao(m.resposta!, () => widget.acoes.irPara(m.resposta!.id)),
        if (m.reuniao != null)
          CartaoReuniao(m.reuniao!, meuId: widget.meuId, aoCancelar: () => widget.acoes.cancelarReuniao(m))
        else if (m.enquete != null)
          _EnqueteView(m, widget.meuId, widget.souAdmin, widget.acoes)
        else if (m.corpo.trim().isNotEmpty || m.html != null)
          TextoMensagem(m, busca: widget.busca),
        if (m.anexos.isNotEmpty) ...[
          if (m.corpo.trim().isNotEmpty) const SizedBox(height: 6),
          AnexosMensagem(widget.api, m.anexos),
        ],
        const SizedBox(height: 3),
        Row(mainAxisSize: MainAxisSize.min, children: [
          if (m.editada) Text('editada · ', style: TextStyle(color: pal.muted, fontSize: 11.5, fontStyle: FontStyle.italic)),
          Text(m.hora, style: TextStyle(color: pal.muted, fontSize: 11.5)),
          if (minha) ...[
            const SizedBox(width: 4),
            Icon(widget.tique == 0 ? Icons.check_rounded : Icons.done_all_rounded,
                size: 15, color: widget.tique == 2 ? const Color(0xFF2563EB) : pal.muted),
          ],
        ]),
      ]),
    );

    final coluna = Column(crossAxisAlignment: minha ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
      if (!minha && widget.grupo)
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 2),
          child: Text(m.autor, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: pal.primary)),
        ),
      GestureDetector(
        onSecondaryTapUp: widget.selecionando ? null : (d) => _menu(d.globalPosition),
        onLongPressStart: widget.selecionando ? null : (d) => _menu(d.globalPosition),
        child: bolha,
      ),
      if (m.reacoes.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Wrap(spacing: 4, runSpacing: 4, children: [
            for (final r in m.reacoes)
              Tooltip(
                message: r.quem.join(', '),
                child: InkWell(
                  borderRadius: BorderRadius.circular(99),
                  onTap: widget.selecionando ? null : () => widget.acoes.reagir(m, r.emoji),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: r.minha ? pal.primary.withValues(alpha: .14) : pal.surface,
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: r.minha ? pal.primary : pal.cardBorder),
                    ),
                    child: Text('${r.emoji} ${r.total}', style: const TextStyle(fontSize: 13)),
                  ),
                ),
              ),
          ]),
        ),
    ]);

    final ferramentas = AnimatedOpacity(
      duration: const Duration(milliseconds: 120),
      opacity: _sobre && !widget.selecionando ? 1 : 0,
      child: IgnorePointer(
        ignoring: !_sobre || widget.selecionando,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(color: pal.card, borderRadius: BorderRadius.circular(10), border: Border.all(color: pal.cardBorder)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            for (final e in reacoesRapidas.take(3))
              InkWell(
                onTap: () => widget.acoes.reagir(m, e),
                child: Padding(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4), child: Text(e, style: const TextStyle(fontSize: 16))),
              ),
            _BotaoMini(Icons.add_reaction_outlined, 'Mais reações', () async {
              final e = await escolherReacao(context);
              if (e != null) widget.acoes.reagir(m, e);
            }),
            _BotaoMini(Icons.reply_rounded, 'Responder', () => widget.acoes.responder(m)),
            Builder(builder: (b) => _BotaoMini(Icons.more_horiz_rounded, 'Mais', () {
                  final box = b.findRenderObject() as RenderBox?;
                  final pos = box == null ? Offset.zero : box.localToGlobal(box.size.bottomLeft(Offset.zero));
                  _menu(pos);
                })),
          ]),
        ),
      ),
    );

    final linha = Row(
      mainAxisAlignment: minha ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (widget.selecionando)
          Padding(
            padding: const EdgeInsets.only(right: 10, bottom: 6),
            child: Icon(widget.selecionada ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                color: widget.selecionada ? pal.primary : pal.muted),
          ),
        if (!minha) ...[
          Avatar(url: m.avatar, nome: m.autor, tam: 30),
          const SizedBox(width: 8),
        ],
        if (minha) ferramentas,
        Flexible(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 620), child: coluna)),
        if (!minha) ferramentas,
      ],
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _sobre = true),
      onExit: (_) => setState(() => _sobre = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
        color: widget.destacada
            ? pal.primary.withValues(alpha: .12)
            : (widget.selecionada ? pal.primary.withValues(alpha: .07) : Colors.transparent),
        child: widget.selecionando && m.enquete == null
            ? InkWell(onTap: widget.alternarSelecao, child: linha)
            : linha,
      ),
    );
  }
}

class _BotaoMini extends StatelessWidget {
  final IconData icone;
  final String dica;
  final VoidCallback onTap;
  const _BotaoMini(this.icone, this.dica, this.onTap);
  @override
  Widget build(BuildContext context) => Tooltip(
        message: dica,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.all(5), child: Icon(icone, size: 18, color: context.pal.muted)),
        ),
      );
}

class _Citacao extends StatelessWidget {
  final Resposta r;
  final VoidCallback onTap;
  const _Citacao(this.r, this.onTap);
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.fromLTRB(10, 5, 10, 5),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border(left: BorderSide(color: p.primary, width: 3)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(r.autor, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: p.primary)),
          Text(r.texto, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 13)),
        ]),
      ),
    );
  }
}

/* ============================ o texto ============================ */

final _reLink = RegExp(r'(https?://[^\s<>"]+|www\.[^\s<>"]+)', caseSensitive: false);

/// O corpo da mensagem: formatação, menções em destaque, links e o realce da busca.
class TextoMensagem extends StatefulWidget {
  final Mensagem m;
  final String busca;
  const TextoMensagem(this.m, {super.key, this.busca = ''});
  @override
  State<TextoMensagem> createState() => _TextoMensagemState();
}

class _TextoMensagemState extends State<TextoMensagem> {
  final List<TapGestureRecognizer> _toques = [];

  @override
  void dispose() {
    for (final t in _toques) {
      t.dispose();
    }
    super.dispose();
  }

  List<Parte> _partes() {
    final m = widget.m;
    if (m.html != null) return partesDoHtml(m.html!);
    // Texto puro: as menções são realçadas pelo nome (como o site faz).
    final texto = m.corpo;
    if (m.mencoes.isEmpty) return [Parte(texto, Estilo.nada)];
    final nomes = m.mencoes.where((n) => n.isNotEmpty).map(RegExp.escape).toList()..sort((a, b) => b.length.compareTo(a.length));
    final re = RegExp('@(${nomes.join('|')})', caseSensitive: false);
    final out = <Parte>[];
    var i = 0;
    for (final x in re.allMatches(texto)) {
      if (x.start > i) out.add(Parte(texto.substring(i, x.start), Estilo.nada));
      out.add(Parte(x.group(0)!, Estilo.nada, mencao: true));
      i = x.end;
    }
    if (i < texto.length) out.add(Parte(texto.substring(i), Estilo.nada));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    for (final t in _toques) {
      t.dispose();
    }
    _toques.clear();
    final pal = context.pal;
    final b = Theme.of(context).brightness;
    final base = TextStyle(fontSize: 14.5, height: 1.42, color: pal.text);
    final busca = widget.busca.trim();
    final spans = <InlineSpan>[];
    for (final parte in _partes()) {
      final e = parte.estilo;
      final est = TextStyle(
        fontWeight: e.b || parte.mencao ? FontWeight.w700 : null,
        fontStyle: e.i ? FontStyle.italic : null,
        decoration: e.u ? TextDecoration.underline : null,
        color: parte.mencao ? pal.primary : (e.cor > 0 ? corChat(e.cor, b, pal.text) : null),
        backgroundColor: parte.mencao ? pal.primary.withValues(alpha: .10) : null,
      );
      var i = 0;
      final t = parte.texto;
      for (final l in _reLink.allMatches(t)) {
        var url = l.group(0)!;
        var resto = '';
        while (url.isNotEmpty && '.,;:!?)'.contains(url[url.length - 1])) {
          resto = url[url.length - 1] + resto;
          url = url.substring(0, url.length - 1);
        }
        _comBusca(spans, t.substring(i, l.start), est, busca);
        final toque = TapGestureRecognizer()..onTap = () => abrirLink(context, url);
        _toques.add(toque);
        spans.add(TextSpan(text: url, style: est.copyWith(color: pal.primary, decoration: TextDecoration.underline), recognizer: toque));
        _comBusca(spans, resto, est, busca);
        i = l.end;
      }
      _comBusca(spans, t.substring(i), est, busca);
    }
    return Text.rich(TextSpan(style: base, children: spans));
  }

  /// Acrescenta o trecho, marcando as ocorrências da busca na conversa.
  void _comBusca(List<InlineSpan> out, String t, TextStyle est, String busca) {
    if (t.isEmpty) return;
    if (busca.length < 2) {
      out.add(TextSpan(text: t, style: est));
      return;
    }
    final alvo = semAcento(t);
    final q = semAcento(busca);
    var i = 0;
    while (true) {
      final j = alvo.indexOf(q, i);
      if (j < 0) break;
      if (j > i) out.add(TextSpan(text: t.substring(i, j), style: est));
      out.add(TextSpan(text: t.substring(j, j + q.length), style: est.copyWith(backgroundColor: const Color(0xFFFDE68A), color: const Color(0xFF3B2A00))));
      i = j + q.length;
    }
    if (i < t.length) out.add(TextSpan(text: t.substring(i), style: est));
  }
}

/* ============================ anexos ============================ */

class AnexosMensagem extends StatelessWidget {
  final Api api;
  final List<Anexo> anexos;
  const AnexosMensagem(this.api, this.anexos, {super.key});

  @override
  Widget build(BuildContext context) {
    final imagens = anexos.where((a) => a.imagem).toList();
    final audios = anexos.where((a) => a.audio && !a.imagem).toList();
    final outros = anexos.where((a) => !a.imagem && !a.audio).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      if (imagens.isNotEmpty)
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (var i = 0; i < imagens.length; i++)
            InkWell(
              onTap: () => abrirImagens(context, api, imagens, i),
              borderRadius: BorderRadius.circular(10),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: ImagemApi(api, imagens[i].miniatura ?? imagens[i].url,
                    largura: imagens.length == 1 ? 260 : 150, altura: imagens.length == 1 ? 190 : 110),
              ),
            ),
        ]),
      for (final a in audios) Padding(padding: const EdgeInsets.only(top: 6), child: PlayerAudio(api, a)),
      for (final a in outros) Padding(padding: const EdgeInsets.only(top: 6), child: _ArquivoChip(api, a)),
    ]);
  }
}

class _ArquivoChip extends StatefulWidget {
  final Api api;
  final Anexo a;
  const _ArquivoChip(this.api, this.a);
  @override
  State<_ArquivoChip> createState() => _ArquivoChipState();
}

class _ArquivoChipState extends State<_ArquivoChip> {
  bool _baixando = false;

  IconData get _icone {
    final n = widget.a.nome.toLowerCase();
    if (n.endsWith('.pdf')) return Icons.picture_as_pdf_outlined;
    if (n.endsWith('.xls') || n.endsWith('.xlsx') || n.endsWith('.csv')) return Icons.table_chart_outlined;
    if (n.endsWith('.doc') || n.endsWith('.docx') || n.endsWith('.txt')) return Icons.description_outlined;
    if (n.endsWith('.zip')) return Icons.folder_zip_outlined;
    return Icons.insert_drive_file_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: _baixando
          ? null
          : () async {
              setState(() => _baixando = true);
              await baixarEAbrir(context, widget.api, widget.a);
              if (mounted) setState(() => _baixando = false);
            },
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
        decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.cardBorder)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(_icone, color: p.primary),
          const SizedBox(width: 8),
          Flexible(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.a.nome, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(_baixando ? 'Baixando…' : [tamanhoLegivel(widget.a.tamanho), 'clique para abrir'].where((s) => s.isNotEmpty).join(' · '),
                  style: TextStyle(color: p.muted, fontSize: 12)),
            ]),
          ),
          const SizedBox(width: 6),
          _baixando ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(Icons.download_rounded, size: 18, color: p.muted),
        ]),
      ),
    );
  }
}

String _nomeSeguro(String n) {
  final s = n.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_').trim();
  return s.isEmpty ? 'arquivo' : s;
}

/// Baixa para a pasta Downloads (sem repetir nome) e abre com o programa do sistema.
Future<void> baixarEAbrir(BuildContext context, Api api, Anexo a, {bool abrir = true}) async {
  try {
    final pasta = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
    final nome = _nomeSeguro(a.nome);
    var destino = File(p.join(pasta.path, nome));
    var n = 2;
    while (destino.existsSync()) {
      destino = File(p.join(pasta.path, '${p.basenameWithoutExtension(nome)} ($n)${p.extension(nome)}'));
      n++;
    }
    await api.baixar(a.url, destino);
    if (abrir) {
      await launchUrl(Uri.file(destino.path));
    }
    if (context.mounted) avisar(context, 'Salvo em ${destino.path}');
  } catch (e) {
    if (context.mounted) avisar(context, erroDe(e), erro: true);
  }
}

/// Áudio tocando na bolha. O arquivo é baixado uma vez (com o token) para a
/// pasta temporária e tocado de lá — o player não manda cabeçalho de autorização.
class PlayerAudio extends StatefulWidget {
  final Api api;
  final Anexo a;
  const PlayerAudio(this.api, this.a, {super.key});

  static final Map<String, String> _locais = {};

  @override
  State<PlayerAudio> createState() => _PlayerAudioState();
}

class _PlayerAudioState extends State<PlayerAudio> {
  // O player nativo só nasce no primeiro "tocar": uma conversa com dezenas de
  // áudios não abre dezenas de players.
  AudioPlayer? _player;
  final List<StreamSubscription> _subs = [];
  Duration _pos = Duration.zero, _dur = Duration.zero;
  bool _tocando = false, _carregando = false;
  String? _erro;

  AudioPlayer _criar() {
    final pl = AudioPlayer();
    _subs.add(pl.onPositionChanged.listen((d) => mounted ? setState(() => _pos = d) : null));
    _subs.add(pl.onDurationChanged.listen((d) => mounted ? setState(() => _dur = d) : null));
    _subs.add(pl.onPlayerStateChanged.listen((s) => mounted ? setState(() => _tocando = s == PlayerState.playing) : null));
    _subs.add(pl.onPlayerComplete.listen((_) => mounted ? setState(() => _pos = Duration.zero) : null));
    return pl;
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player?.dispose();
    super.dispose();
  }

  Future<void> _alternar() async {
    final atual = _player;
    if (atual != null && _tocando) {
      await atual.pause();
      return;
    }
    if (atual != null && atual.source != null) {
      await atual.resume();
      return;
    }
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      var local = PlayerAudio._locais[widget.a.url];
      if (local == null || !File(local).existsSync()) {
        final tmp = await getTemporaryDirectory();
        final ext = p.extension(widget.a.nome).isEmpty ? '.mp3' : p.extension(widget.a.nome);
        final f = File(p.join(tmp.path, 'nn-conversas-audio', '${widget.a.id}-${widget.a.url.hashCode.abs()}$ext'));
        if (!f.existsSync()) await widget.api.baixar(widget.a.url, f);
        local = f.path;
        PlayerAudio._locais[widget.a.url] = local;
      }
      final pl = _player ??= _criar();
      await pl.play(DeviceFileSource(local));
    } catch (e) {
      _erro = 'Não deu para tocar aqui — baixe o áudio.';
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  String _mmss(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final total = _dur.inMilliseconds;
    return Container(
      width: 320,
      padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(99), border: Border.all(color: p.cardBorder)),
      child: Row(children: [
        IconButton(
          onPressed: _carregando ? null : _alternar,
          icon: _carregando
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(_tocando ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded, color: p.primary, size: 30),
          tooltip: _tocando ? 'Pausar' : 'Tocar',
        ),
        Expanded(
          child: _erro != null
              ? Text(_erro!, style: TextStyle(color: p.muted, fontSize: 12))
              : SliderTheme(
                  data: SliderTheme.of(context).copyWith(trackHeight: 3, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6)),
                  child: Slider(
                    value: total == 0 ? 0 : (_pos.inMilliseconds / total).clamp(0, 1).toDouble(),
                    onChanged: total == 0 ? null : (v) => _player?.seek(Duration(milliseconds: (v * total).round())),
                  ),
                ),
        ),
        Text(total == 0 ? widget.a.nome.split('.').last.toUpperCase() : '${_mmss(_pos)} / ${_mmss(_dur)}',
            style: TextStyle(color: p.muted, fontSize: 12, fontFeatures: const [FontFeature.tabularFigures()])),
        IconButton(
          tooltip: 'Baixar o áudio',
          onPressed: () => baixarEAbrir(context, widget.api, widget.a, abrir: false),
          icon: Icon(Icons.download_rounded, size: 18, color: p.muted),
        ),
      ]),
    );
  }
}

/// O visualizador de imagens (tela cheia, ← → entre as imagens, Esc fecha).
Future<void> abrirImagens(BuildContext context, Api api, List<Anexo> imagens, int inicio) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    builder: (_) => _Visualizador(api, imagens, inicio),
  );
}

class _Visualizador extends StatefulWidget {
  final Api api;
  final List<Anexo> imagens;
  final int inicio;
  const _Visualizador(this.api, this.imagens, this.inicio);
  @override
  State<_Visualizador> createState() => _VisualizadorState();
}

class _VisualizadorState extends State<_Visualizador> {
  late int _i = widget.inicio;

  void _ir(int d) {
    final n = (_i + d).clamp(0, widget.imagens.length - 1);
    if (n != _i) setState(() => _i = n);
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.imagens[_i];
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _ir(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _ir(1),
      },
      child: Focus(
        autofocus: true,
        child: Stack(children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(70, 70, 70, 40),
                child: InteractiveViewer(child: ImagemApi(widget.api, a.url, fit: BoxFit.contain, key: ValueKey(a.url))),
              ),
            ),
          ),
          Positioned(
            top: 14,
            left: 20,
            right: 20,
            child: Row(children: [
              Expanded(
                child: Text('${a.nome}${widget.imagens.length > 1 ? '  ·  ${_i + 1} de ${widget.imagens.length}' : ''}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
              ),
              TextButton.icon(
                onPressed: () => baixarEAbrir(context, widget.api, a, abrir: false),
                icon: const Icon(Icons.download_rounded, color: Colors.white),
                label: const Text('Baixar', style: TextStyle(color: Colors.white)),
              ),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, color: Colors.white), tooltip: 'Fechar (Esc)'),
            ]),
          ),
          if (_i > 0)
            Positioned(
              left: 10,
              top: 0,
              bottom: 0,
              child: Center(child: IconButton.filledTonal(onPressed: () => _ir(-1), icon: const Icon(Icons.chevron_left_rounded))),
            ),
          if (_i < widget.imagens.length - 1)
            Positioned(
              right: 10,
              top: 0,
              bottom: 0,
              child: Center(child: IconButton.filledTonal(onPressed: () => _ir(1), icon: const Icon(Icons.chevron_right_rounded))),
            ),
        ]),
      ),
    );
  }
}

/* ============================ enquete ============================ */

class _EnqueteView extends StatelessWidget {
  final Mensagem m;
  final int meuId;
  final bool souAdmin;
  final AcoesMensagem acoes;
  const _EnqueteView(this.m, this.meuId, this.souAdmin, this.acoes);

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final e = m.enquete!;
    final total = e.total;
    return SizedBox(
      width: 380,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Icon(Icons.poll_outlined, size: 18, color: p.primary),
          const SizedBox(width: 6),
          Expanded(child: Text(e.pergunta, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
        ]),
        const SizedBox(height: 2),
        Text(e.multi ? 'Pode marcar mais de uma' : 'Escolha uma', style: TextStyle(color: p.muted, fontSize: 12)),
        const SizedBox(height: 8),
        for (final o in e.opcoes)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: e.encerrada ? null : () => acoes.votar(m, o),
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
                decoration: BoxDecoration(
                  border: Border.all(color: o.minha ? p.primary : p.cardBorder),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Icon(o.minha ? (e.multi ? Icons.check_box_rounded : Icons.radio_button_checked) : (e.multi ? Icons.check_box_outline_blank : Icons.radio_button_unchecked),
                        size: 18, color: o.minha ? p.primary : p.muted),
                    const SizedBox(width: 8),
                    Expanded(child: Text(o.texto)),
                    Text('${total == 0 ? 0 : (o.votos * 100 / total).round()}%', style: TextStyle(color: p.muted, fontSize: 12.5, fontWeight: FontWeight.w600)),
                  ]),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: total == 0 ? 0 : o.votos / total,
                      minHeight: 5,
                      backgroundColor: p.surface,
                      color: p.primary,
                    ),
                  ),
                ]),
              ),
            ),
          ),
        Row(children: [
          Text('$total ${total == 1 ? 'voto' : 'votos'}${e.encerrada ? ' · Encerrada' : ''}', style: TextStyle(color: p.muted, fontSize: 12.5)),
          const Spacer(),
          if (souAdmin) TextButton(onPressed: () => acoes.quemVotou(m), child: const Text('Quem votou')),
          if (!e.encerrada && (e.autorId == meuId || souAdmin)) TextButton(onPressed: () => acoes.encerrarEnquete(m), child: const Text('Encerrar')),
        ]),
      ]),
    );
  }
}

/* ======================== reunião do Google Meet ======================== */

/// O cartão da reunião (na bolha, na lista da conversa e no Início). O estado
/// ("Agendada" → "Acontecendo agora" → "Encerrada") é recalculado pelo relógio a
/// cada 30 s. "Entrar" abre o Meet no navegador: o Google não deixa embutir o
/// vídeo dentro do app.
class CartaoReuniao extends StatefulWidget {
  final Reuniao r;
  final int meuId;
  final VoidCallback? aoCancelar;
  final VoidCallback? aoAbrirConversa; // nas "Próximas reuniões": leva à conversa
  final double largura;
  const CartaoReuniao(this.r, {super.key, required this.meuId, this.aoCancelar, this.aoAbrirConversa, this.largura = 380});

  @override
  State<CartaoReuniao> createState() => _CartaoReuniaoState();
}

const _seloReuniao = {
  'agora': 'Acontecendo agora',
  'agendada': 'Agendada',
  'encerrada': 'Encerrada',
  'cancelada': 'Cancelada',
};

/// O verde do "acontecendo agora" — o mesmo do site (`--meet-cor`), escolhido
/// para o texto branco (claro) e o escuro (escuro) passarem em 4,5:1.
Color corReuniaoAgora(Brightness b) => b == Brightness.dark ? const Color(0xFF4ADE80) : const Color(0xFF0B7A44);

/// Abre no navegador o link do Meet, da Agenda ou do Perfil do site (só http/https;
/// o "Entrar" ainda exige o endereço do Meet — `Reuniao.urlOk`).
Future<void> abrirNoNavegador(String url) async {
  final u = Uri.tryParse(url);
  if (u == null || !(u.scheme == 'https' || u.scheme == 'http')) return;
  await launchUrl(u, mode: LaunchMode.externalApplication);
}

class _CartaoReuniaoState extends State<CartaoReuniao> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && widget.r.estado() != 'cancelada') setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final r = widget.r;
    final est = r.estado();
    final vivo = est == 'agora' || est == 'agendada';
    final verde = corReuniaoAgora(Theme.of(context).brightness);
    final cor = est == 'agora' ? verde : (vivo ? p.primary : p.muted);
    final fundoIcone = est == 'agora' ? verde.withValues(alpha: .14) : (vivo ? p.primary.withValues(alpha: .12) : p.surface);
    final rodape = [
      if (r.organizador.isNotEmpty) 'Organizada por ${r.organizador}',
      if (r.convidados > 0) '${r.convidados} ${r.convidados == 1 ? 'convidado' : 'convidados'}',
    ].join(' · ');

    return Container(
      width: widget.largura,
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: p.cardBorder),
      ),
      clipBehavior: Clip.antiAlias,
      // A faixa da esquerda é um FILHO (borda com cores diferentes + borderRadius
      // é recusada pelo Flutter em execução).
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(width: 4, color: vivo ? cor : p.cardBorder),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(11, 10, 12, 9),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(color: fundoIcone, borderRadius: BorderRadius.circular(9)),
                    child: Icon(Icons.videocam_outlined, size: 19, color: cor),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(
                        r.titulo,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14.5,
                          decoration: est == 'cancelada' ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      Text(r.quando, style: TextStyle(fontSize: 13, color: p.text, fontFeatures: const [FontFeature.tabularFigures()])),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: vivo ? cor.withValues(alpha: .14) : p.surface, borderRadius: BorderRadius.circular(99)),
                    child: Text(_seloReuniao[est] ?? '', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: vivo ? cor : p.text)),
                  ),
                ]),
                if (r.descricao.isNotEmpty) ...[
                  const SizedBox(height: 7),
                  Text(r.descricao, style: const TextStyle(fontSize: 13)),
                ],
                if ((vivo && (r.urlOk || r.agendaOk || (widget.aoCancelar != null && r.podeCancelarPor(widget.meuId)))) ||
                    (widget.aoAbrirConversa != null && r.conversa.isNotEmpty)) ...[
                  const SizedBox(height: 9),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    if (vivo && r.urlOk)
                      FilledButton.icon(
                        onPressed: () => abrirNoNavegador(r.url),
                        style: FilledButton.styleFrom(
                          backgroundColor: est == 'agora' ? verde : null,
                          foregroundColor: est == 'agora' ? tintaSobre(verde) : null,
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: const Icon(Icons.open_in_new_rounded, size: 16),
                        label: const Text('Entrar'),
                      ),
                    if (vivo && r.agendaOk)
                      OutlinedButton(
                        onPressed: () => abrirNoNavegador(r.agendaUrl),
                        style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                        child: const Text('Ver na Agenda'),
                      ),
                    if (vivo && widget.aoCancelar != null && r.podeCancelarPor(widget.meuId))
                      OutlinedButton(
                        onPressed: widget.aoCancelar,
                        style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                        child: const Text('Cancelar reunião'),
                      ),
                    if (widget.aoAbrirConversa != null && r.conversa.isNotEmpty)
                      Tooltip(
                        message: 'Abrir a conversa',
                        child: TextButton.icon(
                          onPressed: widget.aoAbrirConversa,
                          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                          icon: const Icon(Icons.forum_outlined, size: 16),
                          label: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 220),
                            child: Text(r.conversa, maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                        ),
                      ),
                  ]),
                ],
                if (rodape.isNotEmpty) ...[
                  const SizedBox(height: 7),
                  Text(rodape, style: TextStyle(fontSize: 12, color: p.muted)),
                ],
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
