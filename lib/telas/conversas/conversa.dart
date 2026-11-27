// A conversa aberta: cabeçalho (status ou membros), mensagens com divisores de
// dia, carregar as antigas ao rolar, busca com ↑↓, seleção para encaminhar,
// "digitando…", o aviso de status de quem está do outro lado e o compositor.
//
// A lista é INVERTIDA (a mais nova embaixo, índice 0): mensagem nova entra no
// fim sem pular a tela, e as antigas entram no topo ao rolar para cima.
//
// ⚠️ A conversa continua aberta com o app minimizado, atrás de outra janela ou
// noutra aba — e aí ninguém está lendo. Nesses casos a consulta vai com `ler=0`
// (o servidor não marca como lida: quem escreveu não vê "lida" à toa, e a
// mensagem conta nas não lidas e acende a bolinha) e o que chega vira aviso.
// Quando a pessoa volta a olhar, uma consulta na hora marca como lida.
import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

import '../../servicos/alertas.dart';
import '../../servicos/controle.dart';
import '../../tema.dart';
import '../../widgets/comum.dart';
import '../../widgets/topo.dart';
import 'chat_api.dart';
import 'compositor.dart';
import 'dialogos.dart';
import 'mensagem.dart';
import 'tempo_real.dart';

class ConversaView extends StatefulWidget {
  final Controle c;
  final ChatApi chat;
  final TempoReal tempoReal;
  final int id;
  final Conversa? resumo;
  final List<Conversa> recentes;
  final VoidCallback aoMudar;
  final VoidCallback aoSair;
  const ConversaView({
    super.key,
    required this.c,
    required this.chat,
    required this.tempoReal,
    required this.id,
    required this.resumo,
    required this.recentes,
    required this.aoMudar,
    required this.aoSair,
  });

  @override
  State<ConversaView> createState() => _ConversaViewState();
}

class _ConversaViewState extends State<ConversaView> {
  ChatApi get chat => widget.chat;
  final _scroll = ScrollController();
  final _compositor = GlobalKey<CompositorState>();
  final Map<int, GlobalKey> _chaves = {};

  final List<Mensagem> _msgs = [];
  int _ultimo = 0;
  bool _fim = false, _carregandoAntigas = false, _carregou = false;
  String? _erro;

  String _titulo = '';
  String _tipo = 'direct';
  String? _avatar;
  bool _souAdmin = false, _podeExcluir = false;
  List<Participante> _participantes = [];
  EstadoLeitura _leitura = EstadoLeitura.vazio;
  List<String> _digitando = [];

  Mensagem? _respondendo, _editando;
  int? _destacada;
  int _novasAbaixo = 0;

  bool _buscando = false;
  final _busca = TextEditingController();
  List<int> _achados = [];
  int _achadoIdx = 0;

  bool _selecionando = false;
  final Set<int> _sel = {};

  bool _arrastando = false;
  Timer? _tPoll;
  bool _consultando = false;

  bool get _grupo => _tipo == 'group';

  void _ouvinte(String _) => _consultar();

  bool get _olhando => widget.c.alertas.olhando(widget.id);
  bool _olhava = true;

  /// A pessoa voltou a olhar para esta conversa: consulta já (o servidor marca
  /// como lida) e a lista tira as não lidas dela.
  void _atencao() {
    final agora = _olhando;
    if (agora == _olhava) return;
    _olhava = agora;
    // Fora do build de quem avisou (o aviso pode sair no meio de um build).
    _tPoll?.cancel();
    _tPoll = Timer(agora ? const Duration(milliseconds: 250) : const Duration(seconds: 15), _consultar);
  }

  @override
  void initState() {
    super.initState();
    _olhava = _olhando;
    widget.c.alertas.addListener(_atencao);
    _titulo = widget.resumo?.titulo ?? '';
    _tipo = widget.resumo?.tipo ?? 'direct';
    _avatar = widget.resumo?.avatar;
    _scroll.addListener(_rolou);
    widget.tempoReal.aoEvento = _ouvinte;
    unawaited(widget.tempoReal.ouvir(widget.id));
    _carregar();
  }

  @override
  void dispose() {
    _tPoll?.cancel();
    widget.c.alertas.removeListener(_atencao);
    // ⚠️ Só limpa se ainda for o desta conversa: ao trocar de conversa a nova
    // nasce ANTES de esta ser descartada.
    if (widget.tempoReal.aoEvento == _ouvinte) widget.tempoReal.aoEvento = null;
    _scroll.dispose();
    _busca.dispose();
    super.dispose();
  }

  /* ======================= carregar ======================= */

  Future<void> _carregar() async {
    try {
      final r = await chat.mensagens(widget.id, ler: _olhando);
      if (!mounted) return;
      final lista = ((r['messages'] as List?) ?? const []).whereType<Map>().map((m) => Mensagem.de(m.cast<String, dynamic>())).toList();
      setState(() {
        _msgs
          ..clear()
          ..addAll(lista);
        _msgs.sort((a, b) => a.id.compareTo(b.id));
        _ultimo = _msgs.isEmpty ? 0 : _msgs.last.id;
        _fim = lista.length < 100;
        _titulo = (r['title'] ?? _titulo).toString();
        _tipo = (r['type'] ?? _tipo).toString();
        final meta = (r['meta'] as Map?)?.cast<String, dynamic>() ?? const {};
        _souAdmin = meta['is_admin'] == true;
        _podeExcluir = meta['can_delete'] == true;
        if ((meta['avatar'] ?? '').toString().isNotEmpty) _avatar = meta['avatar'].toString();
        _participantes = ((r['participants'] as List?) ?? const [])
            .whereType<Map>()
            .map((x) => Participante((x['id'] as num).toInt(), (x['name'] ?? '').toString()))
            .toList();
        _leitura = EstadoLeitura.de(r['read_state']);
        _digitando = ((r['typing'] as List?) ?? const []).map((e) => '$e').toList();
        _carregou = true;
        _erro = null;
      });
      widget.aoMudar(); // a lista tira o "não lidas" desta conversa
    } catch (e) {
      if (mounted) setState(() => _erro = erroChat(e));
    }
    _agendar();
  }

  void _agendar() {
    _tPoll?.cancel();
    if (!mounted) return;
    // Ninguém olhando: devagar (a lista também consulta, e ela é que avisa a
    // maior parte das vezes).
    final t = widget.tempoReal.conectado || !_olhando ? const Duration(seconds: 15) : const Duration(seconds: 4);
    _tPoll = Timer(t, _consultar);
  }

  /// Só o que mudou desde a última (`?after=`): novas, editadas, reações, leitura e "digitando".
  Future<void> _consultar() async {
    if (_consultando || !mounted || !_carregou) {
      _agendar();
      return;
    }
    _consultando = true;
    try {
      final ler = _olhando;
      final r = await chat.mensagens(widget.id, after: _ultimo, ler: ler);
      if (!mounted) return;
      final novas = ((r['messages'] as List?) ?? const []).whereType<Map>().map((m) => Mensagem.de(m.cast<String, dynamic>())).toList();
      final editadas = ((r['edited'] as List?) ?? const []).whereType<Map>().map((m) => Mensagem.de(m.cast<String, dynamic>())).toList();
      final reacoes = (r['reactions'] as Map?) ?? const {};
      var chegou = 0;
      setState(() {
        for (final m in novas) {
          if (_trocar(m)) continue;
          _msgs.add(m);
          if (!m.minha) chegou++;
        }
        _msgs.sort((a, b) => a.id.compareTo(b.id));
        for (final m in editadas) {
          _trocar(m);
        }
        reacoes.forEach((k, v) {
          final id = int.tryParse('$k') ?? 0;
          final i = _msgs.indexWhere((m) => m.id == id);
          if (i >= 0) _msgs[i].reacoes = Reacao.lista(v);
        });
        if (_msgs.isNotEmpty) _ultimo = _msgs.last.id;
        _leitura = EstadoLeitura.de(r['read_state']);
        _digitando = ((r['typing'] as List?) ?? const []).map((e) => '$e').toList();
        if (chegou > 0 && _scroll.hasClients && _scroll.offset > 160) _novasAbaixo += chegou;
      });
      if (chegou > 0) {
        // Ninguém lendo: aviso (o `Alertas` não repete o que a lista já avisou).
        final dos = novas.where((m) => !m.minha).toList();
        if (!ler && dos.isNotEmpty) {
          final u = dos.last;
          widget.c.alertas.chegou(AvisoMensagem(
            conversa: widget.id,
            titulo: _titulo,
            grupo: _grupo,
            autor: u.autor,
            previa: u.previa,
            avatar: _grupo ? _avatar : (u.avatar ?? _avatar),
            quantas: dos.length,
            ultimoId: u.id,
          ));
        }
        widget.aoMudar();
      }
    } catch (_) {
      // sem rede: a próxima volta tenta
    } finally {
      _consultando = false;
      _agendar();
    }
  }

  bool _trocar(Mensagem m) {
    final i = _msgs.indexWhere((x) => x.id == m.id);
    if (i < 0) return false;
    _msgs[i] = m;
    return true;
  }

  Future<void> _carregarAntigas() async {
    if (_carregandoAntigas || _fim || _msgs.isEmpty) return;
    setState(() => _carregandoAntigas = true);
    try {
      final r = await chat.mensagens(widget.id, before: _msgs.first.id);
      if (!mounted) return;
      final lista = ((r['messages'] as List?) ?? const []).whereType<Map>().map((m) => Mensagem.de(m.cast<String, dynamic>())).toList();
      setState(() {
        for (final m in lista) {
          if (!_trocar(m)) _msgs.add(m);
        }
        _msgs.sort((a, b) => a.id.compareTo(b.id));
        _fim = r['fim'] == true || lista.isEmpty;
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _carregandoAntigas = false);
    }
  }

  void _rolou() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.pixels >= pos.maxScrollExtent - 300) _carregarAntigas();
    if (pos.pixels < 80 && _novasAbaixo > 0) setState(() => _novasAbaixo = 0);
  }

  void _irParaFim() {
    _novasAbaixo = 0;
    if (_scroll.hasClients) _scroll.animateTo(0, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
  }

  /// Leva a uma mensagem (citação, busca): rola até ela ser desenhada, buscando
  /// as antigas quando preciso, e acende por um instante.
  Future<void> _irPara(int id) async {
    for (var tentativa = 0; tentativa < 60 && mounted; tentativa++) {
      final ctx = _chaves[id]?.currentContext;
      if (ctx != null && ctx.mounted) {
        await Scrollable.ensureVisible(ctx, alignment: .4, duration: const Duration(milliseconds: 260));
        if (!mounted) return;
        setState(() => _destacada = id);
        Timer(const Duration(milliseconds: 1600), () {
          if (mounted && _destacada == id) setState(() => _destacada = null);
        });
        return;
      }
      if (!_msgs.any((m) => m.id == id)) {
        if (_fim) break;
        await _carregarAntigas();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        continue;
      }
      if (!_scroll.hasClients) return;
      // Direção: alguma desenhada é mais nova que a procurada → subir (offset maior).
      final desenhadas = _chaves.entries.where((e) => e.value.currentContext != null).map((e) => e.key).toList();
      final subir = desenhadas.isEmpty || desenhadas.any((x) => x > id);
      final passo = _scroll.position.viewportDimension * .8;
      final alvo = (_scroll.offset + (subir ? passo : -passo)).clamp(0.0, _scroll.position.maxScrollExtent);
      _scroll.jumpTo(alvo);
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
    if (mounted) avisar(context, 'Não encontrei essa mensagem.');
  }

  /* ======================= ações ======================= */

  Future<bool> _enviar(String corpo, bool html, List<File> arquivos) async {
    try {
      final m = await chat.enviar(widget.id, corpo: corpo, html: html, responderA: _respondendo?.id, arquivos: arquivos);
      if (!mounted) return true;
      setState(() {
        if (!_trocar(m)) _msgs.add(m);
        _msgs.sort((a, b) => a.id.compareTo(b.id));
        if (m.id > _ultimo) _ultimo = m.id;
        _respondendo = null;
      });
      _irParaFim();
      widget.aoMudar();
      return true;
    } catch (e) {
      if (mounted) avisar(context, erroChat(e), erro: true);
      return false;
    }
  }

  Future<bool> _salvarEdicao(Mensagem m, String corpo, bool html) async {
    try {
      final novo = await chat.editar(m.id, corpo, html);
      if (mounted) setState(() => _trocar(novo));
      return true;
    } catch (e) {
      if (mounted) avisar(context, erroChat(e), erro: true);
      return false;
    }
  }

  Future<void> _reagir(Mensagem m, String emoji) async {
    try {
      final r = await chat.reagir(m.id, emoji);
      if (mounted) setState(() => m.reacoes = r);
    } catch (e) {
      if (mounted) avisar(context, erroChat(e), erro: true);
    }
  }

  Future<void> _votar(Mensagem m, OpcaoEnquete o) async {
    try {
      final e = await chat.votar(m.enquete!.id, o.id);
      if (mounted && e != null) setState(() => m.enquete = e);
    } catch (e) {
      if (mounted) avisar(context, erroChat(e), erro: true);
    }
  }

  Future<void> _encerrarEnquete(Mensagem m) async {
    if (!await confirmar(context, 'Encerrar a enquete?', 'Ninguém mais poderá votar.', 'Encerrar')) return;
    try {
      final e = await chat.encerrarEnquete(m.enquete!.id);
      if (mounted && e != null) setState(() => m.enquete = e);
    } catch (e) {
      if (mounted) avisar(context, erroChat(e), erro: true);
    }
  }

  void _editarUltima() {
    final m = _msgs.reversed.where((x) => x.minha && x.aindaEditavel && x.corpo.trim().isNotEmpty).firstOrNull;
    if (m != null) setState(() => _editando = m);
  }

  Future<void> _encaminharSelecionadas() async {
    final ids = _sel.toList()..sort();
    if (ids.isEmpty) return;
    final foi = await encaminhar(context, chat, ids, widget.recentes);
    if (foi && mounted) {
      setState(() {
        _selecionando = false;
        _sel.clear();
      });
      widget.aoMudar();
    }
  }

  Future<void> _sairDoGrupo() async {
    if (!await confirmar(context, 'Sair do grupo?', 'Você deixa de receber as mensagens de "$_titulo".', 'Sair do grupo', perigo: true)) return;
    try {
      await chat.sair(widget.id);
      widget.aoSair();
    } catch (e) {
      if (mounted) avisar(context, erroChat(e), erro: true);
    }
  }

  Future<void> _excluirGrupo() async {
    if (!await confirmar(context, 'Excluir o grupo?', 'O grupo "$_titulo" e todas as mensagens somem para todos os membros. Isso não tem volta.', 'Excluir grupo',
        perigo: true)) {
      return;
    }
    try {
      await chat.excluir(widget.id);
      widget.aoSair();
    } catch (e) {
      if (mounted) avisar(context, erroChat(e), erro: true);
    }
  }

  void _atualizarBusca() {
    final q = semAcento(_busca.text.trim());
    setState(() {
      _achados = q.length < 2 ? [] : _msgs.reversed.where((m) => semAcento(m.corpo).contains(q)).map((m) => m.id).toList();
      _achadoIdx = 0;
    });
    if (_achados.isNotEmpty) _irPara(_achados.first);
  }

  void _proximoAchado(int d) {
    if (_achados.isEmpty) return;
    final n = _achados.length;
    setState(() => _achadoIdx = ((_achadoIdx + d) % n + n) % n);
    _irPara(_achados[_achadoIdx]);
  }

  /* ======================= tela ======================= */

  String _rotuloDia(String dia) {
    final pd = dia.split('/');
    if (pd.length != 3) return dia;
    final d = DateTime(int.tryParse(pd[2]) ?? 2000, int.tryParse(pd[1]) ?? 1, int.tryParse(pd[0]) ?? 1);
    final agora = DateTime.now();
    final hoje = DateTime(agora.year, agora.month, agora.day);
    final dif = hoje.difference(d).inDays;
    if (dif == 0) return 'Hoje';
    if (dif == 1) return 'Ontem';
    const semana = ['Segunda-feira', 'Terça-feira', 'Quarta-feira', 'Quinta-feira', 'Sexta-feira', 'Sábado', 'Domingo'];
    if (dif > 1 && dif < 7) return semana[d.weekday - 1];
    const meses = ['janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho', 'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro'];
    return '${d.day} de ${meses[d.month - 1]}${d.year != agora.year ? ' de ${d.year}' : ''}';
  }

  /// Criar a reunião do Meet (agora ou agendada); o cartão entra pela consulta.
  Future<void> _novaReuniao() async {
    final r = await novaReuniao(context, chat, widget.id, tituloPadrao: _grupo ? 'Reunião — $_titulo' : 'Reunião com $_titulo');
    if (r == null || !mounted) return;
    final reu = r.$1;
    avisar(context, reu != null && reu.agora ? 'Reunião criada — o Meet abriu no navegador.' : 'Reunião agendada.');
    await _consultar();
  }

  /// A reunião mudou na lista (cancelada): redesenha o cartão da mensagem.
  void _reuniaoMudou(Reuniao r) {
    final i = _msgs.indexWhere((m) => m.reuniao?.id == r.id);
    if (i >= 0) setState(() => _msgs[i].reuniao = r);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final status = widget.resumo?.status;
    final acoes = AcoesMensagem(
      responder: (m) => setState(() {
        _editando = null;
        _respondendo = m;
      }),
      reagir: _reagir,
      editar: (m) => setState(() {
        _respondendo = null;
        _editando = m;
      }),
      encaminhar: (m) => setState(() {
        _selecionando = true;
        _sel
          ..clear()
          ..add(m.id);
      }),
      quemLeu: (m) => quemLeu(context, chat, m.id),
      irPara: _irPara,
      votar: _votar,
      encerrarEnquete: _encerrarEnquete,
      quemVotou: (m) => quemVotou(context, chat, m.enquete!.id),
      cancelarReuniao: (m) async {
        final r = m.reuniao;
        if (r == null) return;
        final nova = await cancelarReuniaoConfirmando(context, chat, r);
        if (nova != null && mounted) setState(() => m.reuniao = nova);
      },
    );

    final cabecalho = _selecionando
        ? Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(color: p.primary.withValues(alpha: .08), border: Border(bottom: BorderSide(color: p.cardBorder))),
            child: Row(children: [
              Icon(Icons.forward_rounded, color: p.primary),
              const SizedBox(width: 10),
              Text('${_sel.length} ${_sel.length == 1 ? 'selecionada' : 'selecionadas'} · clique nas mensagens para marcar', style: const TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              TextButton(onPressed: () => setState(() {
                    _selecionando = false;
                    _sel.clear();
                  }), child: const Text('Cancelar')),
              const SizedBox(width: 6),
              FilledButton.icon(onPressed: _sel.isEmpty ? null : _encaminharSelecionadas, icon: const Icon(Icons.forward_rounded), label: const Text('Encaminhar')),
            ]),
          )
        : Container(
            height: 64,
            padding: const EdgeInsets.fromLTRB(18, 0, 8, 0),
            decoration: BoxDecoration(color: p.card, border: Border(bottom: BorderSide(color: p.cardBorder))),
            child: Row(children: [
              Avatar(url: _avatar, nome: _titulo, tam: 40, ponto: !_grupo && status != null ? PontoStatus(status.codigo, tam: 12) : null),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(_titulo, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  Text(
                    _grupo ? '${_participantes.length} membros' : (status?.texto ?? ''),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.muted, fontSize: 12.5),
                  ),
                ]),
              ),
              IconButton(
                tooltip: 'Buscar na conversa',
                onPressed: () => setState(() {
                  _buscando = !_buscando;
                  if (!_buscando) {
                    _busca.clear();
                    _achados = [];
                  }
                }),
                icon: Icon(Icons.search_rounded, color: _buscando ? p.primary : null),
              ),
              IconButton(
                tooltip: 'Reuniões da conversa',
                onPressed: () => listaReunioes(context, chat, widget.id, meuId: widget.c.meuId, aoNova: _novaReuniao, aoMudar: _reuniaoMudou),
                icon: const Icon(Icons.event_note_outlined),
              ),
              IconButton(
                tooltip: 'Arquivos da conversa',
                onPressed: () => arquivosDaConversa(context, widget.c.api, chat, widget.id),
                icon: const Icon(Icons.attach_file_rounded),
              ),
              PopupMenuButton<String>(
                tooltip: 'Mais',
                onSelected: (v) async {
                  switch (v) {
                    case 'selecionar':
                      setState(() => _selecionando = true);
                    case 'grupo':
                      final mudou = await gerenciarGrupo(context, chat, widget.id, souAdmin: _souAdmin, meuId: widget.c.meuId);
                      if (mudou) {
                        await _carregar();
                        widget.aoMudar();
                      }
                    case 'sair':
                      await _sairDoGrupo();
                    case 'excluir':
                      await _excluirGrupo();
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'selecionar', child: ListTile(dense: true, leading: Icon(Icons.checklist_rounded), title: Text('Selecionar para encaminhar'))),
                  if (_grupo) PopupMenuItem(value: 'grupo', child: ListTile(dense: true, leading: const Icon(Icons.group_outlined), title: Text(_souAdmin ? 'Gerenciar o grupo' : 'Membros do grupo'))),
                  if (_grupo) const PopupMenuItem(value: 'sair', child: ListTile(dense: true, leading: Icon(Icons.logout_rounded), title: Text('Sair do grupo'))),
                  if (_grupo && _podeExcluir)
                    PopupMenuItem(value: 'excluir', child: ListTile(dense: true, leading: Icon(Icons.delete_outline_rounded, color: p.danger), title: Text('Excluir o grupo', style: TextStyle(color: p.danger)))),
                ],
              ),
            ]),
          );

    final barraBusca = !_buscando
        ? const SizedBox.shrink()
        : Container(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
            decoration: BoxDecoration(color: p.surface, border: Border(bottom: BorderSide(color: p.cardBorder))),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _busca,
                  autofocus: true,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Buscar nas mensagens carregadas (2+ letras)'),
                  onChanged: (_) => _atualizarBusca(),
                  onSubmitted: (_) => _proximoAchado(1),
                ),
              ),
              const SizedBox(width: 10),
              Text(_achados.isEmpty ? (_busca.text.trim().length >= 2 ? 'Nada encontrado' : '') : '${_achadoIdx + 1} de ${_achados.length}',
                  style: TextStyle(color: p.muted, fontSize: 12.5)),
              IconButton(tooltip: 'Mais antiga', onPressed: _achados.isEmpty ? null : () => _proximoAchado(1), icon: const Icon(Icons.keyboard_arrow_up_rounded)),
              IconButton(tooltip: 'Mais recente', onPressed: _achados.isEmpty ? null : () => _proximoAchado(-1), icon: const Icon(Icons.keyboard_arrow_down_rounded)),
              if (!_fim)
                TextButton(onPressed: _carregarAntigas, child: const Text('Carregar mais antigas')),
            ]),
          );

    Widget lista;
    if (_erro != null && !_carregou) {
      lista = Center(child: Vazio(Icons.cloud_off_outlined, _erro!));
    } else if (!_carregou) {
      lista = const Center(child: CircularProgressIndicator());
    } else if (_msgs.isEmpty) {
      lista = const Center(child: Vazio(Icons.chat_bubble_outline_rounded, 'Nenhuma mensagem ainda. Escreva a primeira.'));
    } else {
      final q = _buscando ? _busca.text : '';
      lista = ListView.builder(
        controller: _scroll,
        reverse: true,
        padding: const EdgeInsets.symmetric(vertical: 12),
        itemCount: _msgs.length + 1,
        itemBuilder: (_, i) {
          if (i == _msgs.length) {
            return Padding(
              padding: const EdgeInsets.all(12),
              child: Center(
                child: _carregandoAntigas
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(_fim ? 'Início da conversa' : '', style: TextStyle(color: p.muted, fontSize: 12)),
              ),
            );
          }
          final idx = _msgs.length - 1 - i;
          final m = _msgs[idx];
          final anterior = idx > 0 ? _msgs[idx - 1] : null;
          final mostraDia = anterior == null || anterior.dia != m.dia;
          final chave = _chaves.putIfAbsent(m.id, () => GlobalKey());
          return Column(key: chave, children: [
            if (mostraDia)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(children: [
                  Expanded(child: Divider(color: p.cardBorder, indent: 40)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(_rotuloDia(m.dia), style: TextStyle(color: p.muted, fontSize: 12.5, fontWeight: FontWeight.w600)),
                  ),
                  Expanded(child: Divider(color: p.cardBorder, endIndent: 40)),
                ]),
              ),
            BolhaMensagem(
              api: widget.c.api,
              m: m,
              grupo: _grupo,
              souAdmin: _souAdmin,
              meuId: widget.c.meuId,
              tique: m.minha ? _leitura.tique(m.id, widget.c.meuId) : 0,
              acoes: acoes,
              busca: q,
              destacada: _destacada == m.id,
              selecionando: _selecionando,
              selecionada: _sel.contains(m.id),
              alternarSelecao: () {
                if (_sel.contains(m.id)) {
                  setState(() => _sel.remove(m.id));
                } else if (_sel.length >= 50) {
                  avisar(context, 'No máximo 50 mensagens.');
                } else {
                  setState(() => _sel.add(m.id));
                }
              },
            ),
          ]);
        },
      );
    }

    final avisoStatus = !_grupo && status != null && status.avisa
        ? Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(18, 7, 18, 7),
            color: corDoStatus(status.codigo).withValues(alpha: .12),
            child: Row(children: [
              PontoStatus(status.codigo),
              const SizedBox(width: 8),
              Expanded(child: Text('$_titulo: ${status.texto}. A resposta pode demorar.', style: TextStyle(color: p.text, fontSize: 13))),
            ]),
          )
        : const SizedBox.shrink();

    return DropTarget(
      onDragEntered: (_) => setState(() => _arrastando = true),
      onDragExited: (_) => setState(() => _arrastando = false),
      onDragDone: (d) {
        setState(() => _arrastando = false);
        _compositor.currentState?.adicionarArquivos(d.files.map((x) => File(x.path)).toList());
      },
      child: Stack(children: [
        Column(children: [
          cabecalho,
          barraBusca,
          Expanded(
            child: Stack(children: [
              Positioned.fill(child: lista),
              if (_novasAbaixo > 0)
                Positioned(
                  bottom: 12,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: FilledButton.icon(
                      onPressed: _irParaFim,
                      icon: const Icon(Icons.arrow_downward_rounded, size: 18),
                      label: Text('$_novasAbaixo ${_novasAbaixo == 1 ? 'mensagem nova' : 'mensagens novas'}'),
                    ),
                  ),
                ),
            ]),
          ),
          if (_digitando.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _digitando.length == 1 ? '${_digitando.first} está digitando…' : '${_digitando.take(2).join(' e ')} estão digitando…',
                  style: TextStyle(color: p.muted, fontSize: 12.5, fontStyle: FontStyle.italic),
                ),
              ),
            ),
          avisoStatus,
          Compositor(
            key: _compositor,
            arm: widget.c.arm,
            conversaId: widget.id,
            grupo: _grupo,
            meuId: widget.c.meuId,
            participantes: _participantes,
            respondendo: _respondendo,
            editando: _editando,
            cancelarResposta: () => setState(() => _respondendo = null),
            cancelarEdicao: () => setState(() => _editando = null),
            enviar: _enviar,
            salvarEdicao: _salvarEdicao,
            aoDigitar: () => unawaited(chat.digitando(widget.id).catchError((_) {})),
            novaEnquete: () async {
              if (await novaEnquete(context, chat, widget.id)) await _consultar();
            },
            novaReuniao: _novaReuniao,
            aoEditarUltima: _editarUltima,
          ),
        ]),
        if (_arrastando)
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                margin: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: p.primary.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: p.primary, width: 2),
                ),
                alignment: Alignment.center,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.file_download_outlined, size: 44, color: p.primary),
                  const SizedBox(height: 8),
                  Text('Solte para anexar à mensagem', style: TextStyle(color: p.primary, fontWeight: FontWeight.w700, fontSize: 16)),
                  Text('até 10 arquivos de 15 MB', style: TextStyle(color: p.muted)),
                ]),
              ),
            ),
          ),
      ]),
    );
  }
}
