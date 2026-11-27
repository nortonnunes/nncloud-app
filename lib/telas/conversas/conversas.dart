// Conversas — o chat interno do NN Conecta, completo (o mesmo do site):
// lista à esquerda (recolhível, busca sem acento, favoritas no topo com ordem
// arrastável, arquivadas, não lidas, bolinha de status) e a conversa à direita.
//
// ⚠️ A lista é consultada a cada 8 s com a aba aberta (15 s com ela fechada —
// é ela que mantém o contador de não lidas do topo em dia entre as consultas
// do `/eu`, e é comparando uma leitura com a anterior que nascem os avisos de
// mensagem nova: `DetectorConversas`). Ordem dos favoritos: gravada no servidor
// (`/favorites/order`).
import 'dart:async';

import 'package:flutter/material.dart';

import '../../servicos/alertas.dart';
import '../../servicos/controle.dart';
import '../../tema.dart';
import '../../widgets/comum.dart';
import '../../widgets/topo.dart';
import '../casca.dart';
import 'chat_api.dart';
import 'conversa.dart';
import 'dialogos.dart';
import 'tempo_real.dart';

class TelaConversas extends StatefulWidget {
  final Controle c;
  final bool ativa;
  const TelaConversas(this.c, {super.key, required this.ativa});
  @override
  State<TelaConversas> createState() => _TelaConversasState();
}

class _TelaConversasState extends State<TelaConversas> {
  late final ChatApi chat = ChatApi(widget.c.api);
  late final TempoReal tempo = TempoReal(chat);

  List<Conversa> _lista = [];
  List<Conversa> _arquivadas = [];
  bool _verArquivadas = false;
  bool _carregou = false;
  String? _erro;
  String _q = '';
  int? _aberta;
  Timer? _t;
  bool _consultando = false;
  final _detector = DetectorConversas();

  bool get _recolhida => widget.c.arm.pref<bool>('conversas_recolhida', false);

  @override
  void initState() {
    super.initState();
    _carregar();
    _agendar();
    _naTela();
    Casca.conversaPedida.addListener(_pedida);
    WidgetsBinding.instance.addPostFrameCallback((_) => _pedida());
    unawaited(tempo.iniciar());
  }

  @override
  void didUpdateWidget(covariant TelaConversas old) {
    super.didUpdateWidget(old);
    if (widget.ativa != old.ativa) {
      if (widget.ativa) _carregar();
      _agendar();
      _naTela();
    }
  }

  @override
  void dispose() {
    _t?.cancel();
    if (widget.c.alertas.conversaNaTela == _aberta) widget.c.alertas.conversaNaTela = null;
    Casca.conversaPedida.removeListener(_pedida);
    tempo.encerrar();
    super.dispose();
  }

  void _agendar() {
    _t?.cancel();
    _t = Timer.periodic(widget.ativa ? const Duration(seconds: 8) : const Duration(seconds: 15), (_) => _carregar());
  }

  /// Qual conversa está NA TELA agora (a aberta, com a aba Conversas à vista).
  void _naTela() => widget.c.alertas.conversaNaTela = widget.ativa ? _aberta : null;

  void _pedida() {
    final id = Casca.conversaPedida.value;
    if (id == null || id <= 0) return;
    Casca.conversaPedida.value = null;
    _abrir(id);
  }

  Future<void> _carregar() async {
    if (_consultando) return;
    _consultando = true;
    try {
      final l = await chat.conversas();
      final arq = _verArquivadas ? await chat.conversas(arquivadas: true) : _arquivadas;
      if (!mounted) return;
      setState(() {
        _lista = l;
        _arquivadas = arq;
        _carregou = true;
        _erro = null;
      });
      // Mensagem nova: compara com a leitura anterior e avisa (o `Alertas` decide
      // como — e não avisa a conversa que a pessoa está lendo).
      final al = widget.c.alertas;
      for (final a in _detector.comparar([
        for (final c in l)
          ConversaLida(
            id: c.id,
            naoLidas: c.naoLidas,
            ultimoId: c.ultimoId,
            titulo: c.titulo,
            grupo: c.grupo,
            autor: c.ultimoAutor,
            previa: c.previa,
            avatar: c.avatar,
          ),
      ])) {
        al.chegou(a);
      }
      // A conversa que a pessoa está lendo não conta como não lida (o servidor
      // marca ao consultar). Aberta, mas sem ninguém olhando, conta: é ela que
      // acende a bolinha com o app minimizado.
      final total = l.fold<int>(0, (s, c) => s + (al.olhando(c.id) ? 0 : c.naoLidas));
      widget.c.definirNaoLidas(total);
    } catch (e) {
      if (mounted && !_carregou) setState(() => _erro = erroChat(e));
    } finally {
      _consultando = false;
    }
  }

  void _abrir(int id) {
    setState(() => _aberta = id);
    _naTela();
    widget.c.alertas.abriu(id);
    final i = _lista.indexWhere((c) => c.id == id);
    if (i >= 0 && _lista[i].naoLidas > 0) {
      setState(() => _lista[i].naoLidas = 0);
    }
    unawaited(tempo.ouvir(id));
  }

  Future<void> _favoritar(Conversa c) async {
    try {
      final f = await chat.favoritar(c.id);
      setState(() => c.favorita = f);
      await _carregar();
    } catch (e) {
      if (mounted) avisar(context, erroChat(e), erro: true);
    }
  }

  Future<void> _arquivar(Conversa c) async {
    try {
      final a = await chat.arquivar(c.id);
      if (!mounted) return;
      avisar(context, a ? 'Conversa arquivada. Ela volta sozinha quando chegar mensagem nova.' : 'Conversa de volta à lista.');
      if (a && _aberta == c.id) {
        setState(() => _aberta = null);
        _naTela();
      }
      if (_verArquivadas) _arquivadas = await chat.conversas(arquivadas: true);
      await _carregar();
    } catch (e) {
      if (mounted) avisar(context, erroChat(e), erro: true);
    }
  }

  Future<void> _reordenar(List<Conversa> favoritas, int de, int para) async {
    if (para > de) para -= 1;
    final f = [...favoritas];
    final x = f.removeAt(de);
    f.insert(para, x);
    setState(() {
      final resto = _lista.where((c) => !c.favorita).toList();
      _lista = [...f, ...resto];
    });
    try {
      await chat.ordemFavoritos(f.map((c) => c.id).toList());
    } catch (e) {
      if (mounted) avisar(context, erroChat(e), erro: true);
      await _carregar();
    }
  }

  Future<void> _menu(Conversa c, Offset pos) async {
    final r = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx + 1, pos.dy + 1),
      items: [
        PopupMenuItem(value: 'fav', child: ListTile(dense: true, leading: Icon(c.favorita ? Icons.star_rounded : Icons.star_border_rounded), title: Text(c.favorita ? 'Tirar dos favoritos' : 'Favoritar'))),
        PopupMenuItem(value: 'arq', child: ListTile(dense: true, leading: Icon(c.arquivada ? Icons.unarchive_outlined : Icons.archive_outlined), title: Text(c.arquivada ? 'Desarquivar' : 'Arquivar'))),
      ],
    );
    if (r == 'fav') await _favoritar(c);
    if (r == 'arq') await _arquivar(c);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final recolhida = _recolhida;
    final fonte = _verArquivadas ? _arquivadas : _lista;
    final q = semAcento(_q.trim());
    final filtrada = q.isEmpty ? fonte : fonte.where((c) => semAcento('${c.titulo} ${c.previa}').contains(q)).toList();
    final favoritas = _verArquivadas || q.isNotEmpty ? <Conversa>[] : filtrada.where((c) => c.favorita).toList();
    final demais = favoritas.isEmpty ? filtrada : filtrada.where((c) => !c.favorita).toList();
    Conversa? resumo;
    for (final c in [..._lista, ..._arquivadas]) {
      if (c.id == _aberta) resumo = c;
    }

    final cabeca = recolhida
        ? Column(children: [
            const SizedBox(height: 10),
            IconButton(tooltip: 'Abrir a lista', onPressed: () => setState(() => widget.c.arm.definir('conversas_recolhida', false)), icon: const Icon(Icons.keyboard_double_arrow_right_rounded)),
            IconButton(tooltip: 'Nova conversa', onPressed: _nova, icon: const Icon(Icons.edit_square)),
          ])
        : Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
            child: Column(children: [
              Row(children: [
                Expanded(child: Text(_verArquivadas ? 'Arquivadas' : 'Conversas', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20))),
                IconButton(tooltip: 'Nova conversa', onPressed: _nova, icon: const Icon(Icons.edit_square)),
                IconButton(tooltip: 'Novo grupo', onPressed: _novoGrupo, icon: const Icon(Icons.group_add_outlined)),
                IconButton(
                  tooltip: _verArquivadas ? 'Voltar às conversas' : 'Ver arquivadas',
                  onPressed: () async {
                    setState(() => _verArquivadas = !_verArquivadas);
                    if (_verArquivadas) {
                      try {
                        final a = await chat.conversas(arquivadas: true);
                        if (mounted) setState(() => _arquivadas = a);
                      } catch (_) {}
                    }
                  },
                  icon: Icon(_verArquivadas ? Icons.inbox_outlined : Icons.archive_outlined),
                ),
                IconButton(tooltip: 'Recolher a lista', onPressed: () => setState(() => widget.c.arm.definir('conversas_recolhida', true)), icon: const Icon(Icons.keyboard_double_arrow_left_rounded)),
              ]),
              const SizedBox(height: 6),
              TextField(
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Buscar conversa'),
                onChanged: (v) => setState(() => _q = v),
              ),
            ]),
          );

    Widget item(Conversa c, {bool arrastavel = false, int? indice}) => _ItemConversa(
          c: c,
          aberta: c.id == _aberta,
          recolhida: recolhida,
          onTap: () => _abrir(c.id),
          onMenu: (pos) => _menu(c, pos),
          alca: arrastavel && indice != null && !recolhida
              ? ReorderableDragStartListener(index: indice, child: Padding(padding: const EdgeInsets.all(4), child: Icon(Icons.drag_indicator_rounded, size: 18, color: p.muted)))
              : null,
        );

    Widget corpoLista;
    if (_erro != null && !_carregou) {
      corpoLista = Vazio(Icons.cloud_off_outlined, _erro!);
    } else if (!_carregou) {
      corpoLista = const Center(child: Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator()));
    } else if (filtrada.isEmpty) {
      corpoLista = Vazio(Icons.forum_outlined, q.isNotEmpty ? 'Nenhuma conversa encontrada.' : (_verArquivadas ? 'Nenhuma conversa arquivada.' : 'Nenhuma conversa ainda.'));
    } else {
      corpoLista = CustomScrollView(slivers: [
        if (favoritas.isNotEmpty && !recolhida)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
              child: Text('Favoritas', style: TextStyle(color: p.muted, fontWeight: FontWeight.w700, fontSize: 12)),
            ),
          ),
        if (favoritas.isNotEmpty)
          SliverReorderableList(
            itemCount: favoritas.length,
            onReorder: (a, b) => _reordenar(favoritas, a, b),
            itemBuilder: (_, i) => Material(key: ValueKey('f${favoritas[i].id}'), color: Colors.transparent, child: item(favoritas[i], arrastavel: true, indice: i)),
          ),
        if (favoritas.isNotEmpty && demais.isNotEmpty && !recolhida)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
              child: Text('Conversas', style: TextStyle(color: p.muted, fontWeight: FontWeight.w700, fontSize: 12)),
            ),
          ),
        SliverList.builder(itemCount: demais.length, itemBuilder: (_, i) => item(demais[i])),
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
      ]);
    }

    return Row(children: [
      AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: recolhida ? 76 : 370,
        decoration: BoxDecoration(color: p.card, border: Border(right: BorderSide(color: p.cardBorder))),
        child: Column(children: [cabeca, Expanded(child: corpoLista)]),
      ),
      Expanded(
        child: _aberta == null
            ? Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.forum_outlined, size: 64, color: p.muted.withValues(alpha: .6)),
                  const SizedBox(height: 12),
                  const Text('Escolha uma conversa', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text('ou comece uma nova com quem você precisa falar.', style: TextStyle(color: p.muted)),
                  const SizedBox(height: 16),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    FilledButton.icon(onPressed: _nova, icon: const Icon(Icons.edit_square), label: const Text('Nova conversa')),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(onPressed: _novoGrupo, icon: const Icon(Icons.group_add_outlined), label: const Text('Novo grupo')),
                  ]),
                ]),
              )
            : ConversaView(
                key: ValueKey(_aberta),
                c: widget.c,
                chat: chat,
                tempoReal: tempo,
                id: _aberta!,
                resumo: resumo,
                recentes: _lista,
                aoMudar: () => unawaited(_carregar()),
                aoSair: () {
                  setState(() => _aberta = null);
                  _naTela();
                  unawaited(tempo.ouvir(null));
                  unawaited(_carregar());
                },
              ),
      ),
    ]);
  }

  Future<void> _nova() async {
    final id = await novaConversa(context, chat);
    if (id == null || !mounted) return;
    await _carregar();
    _abrir(id);
  }

  Future<void> _novoGrupo() async {
    final id = await novoGrupo(context, chat);
    if (id == null || !mounted) return;
    await _carregar();
    _abrir(id);
  }
}

class _ItemConversa extends StatelessWidget {
  final Conversa c;
  final bool aberta, recolhida;
  final VoidCallback onTap;
  final void Function(Offset) onMenu;
  final Widget? alca;
  const _ItemConversa({required this.c, required this.aberta, required this.recolhida, required this.onTap, required this.onMenu, this.alca});

  String _hora() {
    final d = DateTime.tryParse(c.atualizada.replaceFirst(' ', 'T'));
    if (d == null) return '';
    final agora = DateTime.now();
    if (d.year == agora.year && d.month == agora.month && d.day == agora.day) {
      return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    }
    final ontem = agora.subtract(const Duration(days: 1));
    if (d.year == ontem.year && d.month == ontem.month && d.day == ontem.day) return 'ontem';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final ponto = !c.grupo && c.status != null ? PontoStatus(c.status!.codigo, tam: 11) : null;
    final avatar = Stack(clipBehavior: Clip.none, children: [
      Avatar(url: c.avatar, nome: c.titulo, tam: 44, ponto: ponto),
      if (recolhida && c.naoLidas > 0)
        Positioned(right: -4, top: -4, child: _Selo(c.naoLidas)),
    ]);
    return Tooltip(
      message: recolhida ? c.titulo : '',
      waitDuration: const Duration(milliseconds: 400),
      child: GestureDetector(
        onSecondaryTapUp: (d) => onMenu(d.globalPosition),
        child: InkWell(
          onTap: onTap,
          onLongPress: () {
            final box = context.findRenderObject() as RenderBox?;
            onMenu(box == null ? Offset.zero : box.localToGlobal(const Offset(40, 30)));
          },
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            padding: EdgeInsets.symmetric(horizontal: recolhida ? 8 : 10, vertical: 9),
            decoration: BoxDecoration(
              color: aberta ? p.primary.withValues(alpha: .10) : null,
              borderRadius: BorderRadius.circular(12),
            ),
            child: recolhida
                ? Center(child: avatar)
                : Row(children: [
                    avatar,
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          if (c.grupo) ...[Icon(Icons.group_outlined, size: 15, color: p.muted), const SizedBox(width: 4)],
                          Expanded(
                            child: Text(c.titulo,
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: c.naoLidas > 0 ? FontWeight.w800 : FontWeight.w600)),
                          ),
                          Text(_hora(), style: TextStyle(color: c.naoLidas > 0 ? p.primary : p.muted, fontSize: 11.5)),
                        ]),
                        const SizedBox(height: 2),
                        Row(children: [
                          Expanded(
                            child: Text(c.previa.isEmpty ? (c.grupo ? 'Grupo' : '') : c.previa,
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 13)),
                          ),
                          if (c.favorita) Icon(Icons.star_rounded, size: 15, color: const Color(0xFFD4A106).withValues(alpha: .9)),
                          if (c.naoLidas > 0) ...[const SizedBox(width: 4), _Selo(c.naoLidas)],
                        ]),
                      ]),
                    ),
                    if (alca != null) alca!,
                  ]),
          ),
        ),
      ),
    );
  }
}

class _Selo extends StatelessWidget {
  final int n;
  const _Selo(this.n);
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: p.primary, borderRadius: BorderRadius.circular(99), border: Border.all(color: p.card, width: 1.5)),
      child: Text(n > 99 ? '99+' : '$n', textAlign: TextAlign.center, style: TextStyle(color: tintaSobre(p.primary), fontSize: 11, fontWeight: FontWeight.w800)),
    );
  }
}
