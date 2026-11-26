// O compositor — o mesmo do chat do site:
//   · negrito, itálico, sublinhado e as 7 cores (vira o HTML que o servidor aceita);
//   · emojis (os 4 grupos), @menções com sugestão (setas, Enter/Tab, Esc);
//   · Enter envia, Shift+Enter quebra a linha; Ctrl/⌘+B/I/U formatam;
//   · até 10 anexos de 15 MB (escolher, arrastar para a conversa ou colar print);
//   · responder/editar com a barra acima; rascunho por conversa, guardado no PC.
import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../servicos/armazenamento.dart';
import '../../tema.dart';
import '../../widgets/comum.dart';
import 'chat_api.dart';
import 'emoji.dart';
import 'formato.dart';

const extensoesPermitidas = [
  'jpg', 'jpeg', 'png', 'gif', 'webp',
  'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx',
  'txt', 'csv', 'zip',
  'mp3', 'm4a', 'aac', 'ogg', 'oga', 'opus', 'wav',
];
const maxAnexos = 10;
const maxBytesAnexo = 15 * 1024 * 1024;

class Compositor extends StatefulWidget {
  final Armazenamento arm;
  final int conversaId;
  final bool grupo;
  final int meuId;
  final List<Participante> participantes;
  final Mensagem? respondendo;
  final Mensagem? editando;
  final VoidCallback cancelarResposta;
  final VoidCallback cancelarEdicao;
  final Future<bool> Function(String corpo, bool html, List<File> arquivos) enviar;
  final Future<bool> Function(Mensagem m, String corpo, bool html) salvarEdicao;
  final VoidCallback aoDigitar;
  final VoidCallback novaEnquete;
  final VoidCallback? aoEditarUltima; // seta para cima com o campo vazio
  const Compositor({
    super.key,
    required this.arm,
    required this.conversaId,
    required this.grupo,
    required this.meuId,
    required this.participantes,
    required this.respondendo,
    required this.editando,
    required this.cancelarResposta,
    required this.cancelarEdicao,
    required this.enviar,
    required this.salvarEdicao,
    required this.aoDigitar,
    required this.novaEnquete,
    this.aoEditarUltima,
  });

  @override
  State<Compositor> createState() => CompositorState();
}

class CompositorState extends State<Compositor> {
  final _c = ControladorFormatado();
  final _foco = FocusNode();
  final List<File> _fila = [];
  bool _enviando = false;
  Timer? _tRascunho;
  DateTime _ultimoDigitando = DateTime.fromMillisecondsSinceEpoch(0);

  // @menções
  List<Participante> _sugestoes = [];
  int _sugIdx = 0;
  int _mencaoIni = -1;

  String get _chaveRascunho => 'rascunho_${widget.conversaId}';

  @override
  void initState() {
    super.initState();
    _restaurarRascunho();
    _c.addListener(_mudou);
    WidgetsBinding.instance.addPostFrameCallback((_) => _foco.requestFocus());
  }

  @override
  void didUpdateWidget(covariant Compositor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.editando?.id != oldWidget.editando?.id) {
      if (widget.editando != null) {
        _salvarRascunhoJa();
        final m = widget.editando!;
        _c.carregar(m.html ?? m.corpo, html: m.html != null);
      } else {
        _restaurarRascunho();
      }
      _foco.requestFocus();
    }
    if (widget.respondendo != null && widget.respondendo?.id != oldWidget.respondendo?.id) _foco.requestFocus();
  }

  @override
  void dispose() {
    _tRascunho?.cancel();
    if (widget.editando == null) _salvarRascunhoJa();
    _c.dispose();
    _foco.dispose();
    super.dispose();
  }

  void focar() => _foco.requestFocus();

  /* ------------------------- rascunho ------------------------- */

  void _restaurarRascunho() {
    final r = widget.arm.pref<String>(_chaveRascunho, '');
    if (r.isEmpty) {
      _c.limpar();
    } else {
      _c.carregar(r, html: true);
    }
  }

  void _salvarRascunhoJa() {
    _tRascunho?.cancel();
    if (widget.editando != null) return;
    try {
      widget.arm.definir(_chaveRascunho, _c.vazio ? null : _c.paraHtml());
    } catch (_) {}
  }

  void _mudou() {
    if (!mounted) return;
    _c.brilho = Theme.of(context).brightness;
    if (widget.editando == null) {
      _tRascunho?.cancel();
      _tRascunho = Timer(const Duration(milliseconds: 400), _salvarRascunhoJa);
    }
    final agora = DateTime.now();
    if (!_c.vazio && agora.difference(_ultimoDigitando).inSeconds >= 3) {
      _ultimoDigitando = agora;
      widget.aoDigitar();
    }
    _procurarMencao();
    setState(() {});
  }

  /* ------------------------- menções ------------------------- */

  void _procurarMencao() {
    final s = _c.selection;
    if (!s.isValid || !s.isCollapsed) return _fecharMencao();
    final antes = _c.text.substring(0, s.start);
    final m = RegExp(r'(^|\s)@([^\s@]{0,30})$').firstMatch(antes);
    if (m == null) return _fecharMencao();
    final q = semAcento(m.group(2)!);
    final lista = widget.participantes
        .where((x) => x.id != widget.meuId && (q.isEmpty || semAcento(x.nome).split(' ').any((w) => w.startsWith(q)) || semAcento(x.nome).startsWith(q)))
        .take(8)
        .toList();
    if (lista.isEmpty) return _fecharMencao();
    _mencaoIni = antes.length - m.group(2)!.length - 1;
    _sugestoes = lista;
    if (_sugIdx >= lista.length) _sugIdx = 0;
  }

  void _fecharMencao() {
    _sugestoes = [];
    _sugIdx = 0;
    _mencaoIni = -1;
  }

  void _escolherMencao(Participante x) {
    final s = _c.selection;
    if (_mencaoIni < 0 || !s.isValid) return;
    final texto = '@${x.nome} ';
    final novo = _c.text.replaceRange(_mencaoIni, s.start, texto);
    final cursor = _mencaoIni + texto.length;
    _fecharMencao();
    _c.value = TextEditingValue(text: novo, selection: TextSelection.collapsed(offset: cursor));
    _foco.requestFocus();
  }

  /* ------------------------- anexos ------------------------- */

  /// Acrescenta arquivos à fila (do botão, do arrastar ou do colar).
  void adicionarArquivos(List<File> arquivos) {
    final recusas = <String>[];
    for (final f in arquivos) {
      final ext = p.extension(f.path).replaceFirst('.', '').toLowerCase();
      final nome = p.basename(f.path);
      if (_fila.length >= maxAnexos) {
        recusas.add('No máximo $maxAnexos anexos por mensagem.');
        break;
      }
      if (!extensoesPermitidas.contains(ext)) {
        recusas.add('$nome: tipo de arquivo não permitido.');
        continue;
      }
      int tam;
      try {
        tam = f.lengthSync();
      } catch (_) {
        recusas.add('$nome: não consegui ler o arquivo.');
        continue;
      }
      if (tam > maxBytesAnexo) {
        recusas.add('$nome: passa de 15 MB.');
        continue;
      }
      if (_fila.any((x) => x.path == f.path)) continue;
      _fila.add(f);
    }
    setState(() {});
    if (recusas.isNotEmpty) avisar(context, recusas.join('\n'), erro: true);
    _foco.requestFocus();
  }

  Future<void> _escolherArquivos() async {
    final r = await FilePicker.platform.pickFiles(allowMultiple: true, type: FileType.custom, allowedExtensions: extensoesPermitidas);
    if (r == null) return;
    adicionarArquivos(r.files.where((f) => f.path != null).map((f) => File(f.path!)).toList());
  }

  int _seqPrint = 0;

  /// Ctrl/⌘+V: arquivo copiado → anexo; print → anexo PNG; senão, o texto.
  Future<void> _colar() async {
    try {
      final arquivos = await Pasteboard.files();
      if (arquivos.isNotEmpty) {
        adicionarArquivos(arquivos.map(File.new).toList());
        return;
      }
      final img = await Pasteboard.image;
      if (img != null && img.isNotEmpty) {
        final tmp = await getTemporaryDirectory();
        final agora = DateTime.now();
        String dd(int n) => n.toString().padLeft(2, '0');
        _seqPrint++;
        final nome = 'print-${agora.year}${dd(agora.month)}${dd(agora.day)}-${dd(agora.hour)}${dd(agora.minute)}${dd(agora.second)}-$_seqPrint.png';
        final f = File(p.join(tmp.path, 'conecta-callcenter-prints', nome));
        f.parent.createSync(recursive: true);
        f.writeAsBytesSync(img);
        adicionarArquivos([f]);
        return;
      }
    } catch (_) {
      // sem acesso à área de transferência: cai no texto
    }
    final t = await Clipboard.getData(Clipboard.kTextPlain);
    final texto = (t?.text ?? '').replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    if (texto.isNotEmpty) _c.inserir(texto);
  }

  /* ------------------------- enviar ------------------------- */

  Future<void> _enviar() async {
    if (_enviando) return;
    final corpoVazio = _c.vazio;
    final editando = widget.editando;
    if (editando != null) {
      if (corpoVazio) return;
      setState(() => _enviando = true);
      final ok = await widget.salvarEdicao(editando, _c.formatado ? _c.paraHtml() : _c.text.trim(), _c.formatado);
      if (mounted) setState(() => _enviando = false);
      if (ok) widget.cancelarEdicao();
      return;
    }
    if (corpoVazio && _fila.isEmpty) return;
    setState(() => _enviando = true);
    final html = _c.formatado;
    final corpo = html ? _c.paraHtml() : _c.text.trim();
    final arquivos = List<File>.from(_fila);
    final ok = await widget.enviar(corpo, html, arquivos);
    if (!mounted) return;
    setState(() => _enviando = false);
    if (ok) {
      _c.limpar();
      _fila.clear();
      widget.arm.definir(_chaveRascunho, null);
      setState(() {});
    }
    _foco.requestFocus();
  }

  KeyEventResult _tecla(FocusNode n, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final hw = HardwareKeyboard.instance;
    final mod = Platform.isMacOS ? hw.isMetaPressed : hw.isControlPressed;

    if (_sugestoes.isNotEmpty) {
      if (k == LogicalKeyboardKey.arrowDown) {
        setState(() => _sugIdx = (_sugIdx + 1) % _sugestoes.length);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.arrowUp) {
        setState(() => _sugIdx = (_sugIdx - 1 + _sugestoes.length) % _sugestoes.length);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter || k == LogicalKeyboardKey.tab) {
        _escolherMencao(_sugestoes[_sugIdx]);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.escape) {
        setState(_fecharMencao);
        return KeyEventResult.handled;
      }
    }
    if ((k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) && !hw.isShiftPressed && !mod) {
      _enviar();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.escape) {
      if (widget.editando != null) {
        widget.cancelarEdicao();
        return KeyEventResult.handled;
      }
      if (widget.respondendo != null) {
        widget.cancelarResposta();
        return KeyEventResult.handled;
      }
    }
    if (k == LogicalKeyboardKey.arrowUp && _c.text.isEmpty && widget.editando == null && widget.aoEditarUltima != null) {
      widget.aoEditarUltima!();
      return KeyEventResult.handled;
    }
    if (mod) {
      if (k == LogicalKeyboardKey.keyB) {
        _c.alternarNegrito();
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.keyI) {
        _c.alternarItalico();
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.keyU) {
        _c.alternarSublinhado();
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.keyV) {
        _colar();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  /* ------------------------- tela ------------------------- */

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    _c.brilho = Theme.of(context).brightness;
    _c.corTexto = pal.text;
    final atual = _c.atual;
    final r = widget.respondendo;
    final ed = widget.editando;
    return Container(
      decoration: BoxDecoration(color: pal.card, border: Border(top: BorderSide(color: pal.cardBorder))),
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (ed != null)
          _Barra(Icons.edit_outlined, 'Editando a mensagem', ed.corpo, widget.cancelarEdicao)
        else if (r != null)
          _Barra(Icons.reply_rounded, 'Respondendo a ${r.autor}', r.corpo.isNotEmpty ? r.corpo : (r.anexos.isNotEmpty ? '📎 ${r.anexos.first.nome}' : ''), widget.cancelarResposta),
        if (_fila.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final f in _fila) _ChipArquivo(f, () => setState(() => _fila.remove(f))),
            ]),
          ),
        if (_sugestoes.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            constraints: const BoxConstraints(maxHeight: 240, maxWidth: 360),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(color: pal.card, borderRadius: BorderRadius.circular(10), border: Border.all(color: pal.cardBorder),
                boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 12, offset: Offset(0, 4))]),
            child: ListView(shrinkWrap: true, padding: const EdgeInsets.symmetric(vertical: 4), children: [
              for (var i = 0; i < _sugestoes.length; i++)
                InkWell(
                  onTap: () => _escolherMencao(_sugestoes[i]),
                  child: Container(
                    color: i == _sugIdx ? pal.primary.withValues(alpha: .10) : null,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(children: [
                      Text('@', style: TextStyle(color: pal.primary, fontWeight: FontWeight.w800)),
                      const SizedBox(width: 6),
                      Expanded(child: Text(_sugestoes[i].nome, overflow: TextOverflow.ellipsis)),
                    ]),
                  ),
                ),
            ]),
          ),
        Row(children: [
          _Ferramenta(Icons.format_bold_rounded, 'Negrito (${_atalho('B')})', atual.b, _c.alternarNegrito),
          _Ferramenta(Icons.format_italic_rounded, 'Itálico (${_atalho('I')})', atual.i, _c.alternarItalico),
          _Ferramenta(Icons.format_underlined_rounded, 'Sublinhado (${_atalho('U')})', atual.u, _c.alternarSublinhado),
          PopupMenuButton<int>(
            tooltip: 'Cor do texto',
            onSelected: (i) {
              _c.definirCor(i);
              _foco.requestFocus();
            },
            itemBuilder: (_) => [
              for (var i = 0; i < coresChat.length; i++)
                PopupMenuItem(
                  value: i,
                  child: Row(children: [
                    Container(width: 16, height: 16, decoration: BoxDecoration(color: i == 0 ? pal.text : corChat(i, Theme.of(context).brightness, pal.text), shape: BoxShape.circle)),
                    const SizedBox(width: 10),
                    Text(nomesCoresChat[i]),
                  ]),
                ),
            ],
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(Icons.format_color_text_rounded, size: 20, color: atual.cor > 0 ? corChat(atual.cor, Theme.of(context).brightness, pal.text) : pal.muted),
            ),
          ),
          Container(width: 1, height: 20, margin: const EdgeInsets.symmetric(horizontal: 6), color: pal.cardBorder),
          _Ferramenta(Icons.emoji_emotions_outlined, 'Emojis', false, () => abrirEmojis(context, (e) => _c.inserir(e))),
          if (ed == null) _Ferramenta(Icons.attach_file_rounded, 'Anexar arquivos (até 10, 15 MB cada)', false, _escolherArquivos),
          if (ed == null && widget.grupo) _Ferramenta(Icons.poll_outlined, 'Nova enquete', false, widget.novaEnquete),
          const Spacer(),
          Text('Enter envia · Shift+Enter quebra a linha', style: TextStyle(color: pal.muted, fontSize: 11.5)),
        ]),
        const SizedBox(height: 4),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: Focus(
              onKeyEvent: _tecla,
              child: TextField(
                controller: _c,
                focusNode: _foco,
                minLines: 1,
                maxLines: 6,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
                style: TextStyle(fontSize: 14.5, color: pal.text, height: 1.35),
                decoration: InputDecoration(hintText: ed != null ? 'Edite a mensagem…' : 'Escreva uma mensagem… (@ para mencionar)'),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 44,
            child: FilledButton(
              onPressed: _enviando ? null : _enviar,
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 18)),
              child: _enviando
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(ed != null ? Icons.check_rounded : Icons.send_rounded, size: 18),
                      const SizedBox(width: 6),
                      Text(ed != null ? 'Salvar' : 'Enviar'),
                    ]),
            ),
          ),
        ]),
      ]),
    );
  }

  String _atalho(String l) => Platform.isMacOS ? '⌘$l' : 'Ctrl+$l';
}

class _Ferramenta extends StatelessWidget {
  final IconData icone;
  final String dica;
  final bool ativo;
  final VoidCallback onTap;
  const _Ferramenta(this.icone, this.dica, this.ativo, this.onTap);
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Tooltip(
      message: dica,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: ativo ? p.primary.withValues(alpha: .14) : null, borderRadius: BorderRadius.circular(8)),
          child: Icon(icone, size: 20, color: ativo ? p.primary : p.muted),
        ),
      ),
    );
  }
}

class _Barra extends StatelessWidget {
  final IconData icone;
  final String titulo, texto;
  final VoidCallback fechar;
  const _Barra(this.icone, this.titulo, this.texto, this.fechar);
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(8), border: Border(left: BorderSide(color: p.primary, width: 3))),
      child: Row(children: [
        Icon(icone, size: 18, color: p.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(titulo, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: p.primary)),
            if (texto.isNotEmpty) Text(texto, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 13)),
          ]),
        ),
        IconButton(onPressed: fechar, icon: const Icon(Icons.close_rounded, size: 18), tooltip: 'Cancelar (Esc)'),
      ]),
    );
  }
}

class _ChipArquivo extends StatelessWidget {
  final File f;
  final VoidCallback remover;
  const _ChipArquivo(this.f, this.remover);
  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final nome = p.basename(f.path);
    final ext = p.extension(nome).toLowerCase();
    final imagem = ['.jpg', '.jpeg', '.png', '.gif', '.webp'].contains(ext);
    int tam = 0;
    try {
      tam = f.lengthSync();
    } catch (_) {}
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
      decoration: BoxDecoration(color: pal.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: pal.cardBorder)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: imagem
              ? Image.file(f, width: 40, height: 40, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox(width: 40, height: 40))
              : Container(width: 40, height: 40, color: pal.card, child: Icon(Icons.insert_drive_file_outlined, color: pal.primary)),
        ),
        const SizedBox(width: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 180),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(nome, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
            Text(tamanhoLegivel(tam), style: TextStyle(color: pal.muted, fontSize: 11.5)),
          ]),
        ),
        IconButton(onPressed: remover, icon: const Icon(Icons.close_rounded, size: 16), tooltip: 'Tirar'),
      ]),
    );
  }
}
