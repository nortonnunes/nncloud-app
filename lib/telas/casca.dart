// A casca da sessão: o topo igual ao do NN Conecta (faixa da logo + barra em
// onda), o menu (Início · Conversas · NN News · Avisos · Minimizar), o conteúdo
// e, por cima de tudo, o COMUNICADO (que só sai com "Entendi").
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config.dart';
import '../servicos/atualizacao.dart';
import '../servicos/controle.dart';
import '../servicos/janela.dart';
import '../servicos/sistema.dart';
import '../servicos/som.dart';
import '../tema.dart';
import '../widgets/comum.dart';
import '../widgets/rodape.dart';
import '../widgets/topo.dart';
import 'acesso.dart';
import 'avisos.dart';
import 'conversas/conversas.dart';
import 'inicio.dart';
import 'news.dart';

class Casca extends StatefulWidget {
  final Controle c;
  final Atualizador atualizador;
  final Future<void> Function() aoMinimizar;
  const Casca(this.c, this.atualizador, {super.key, required this.aoMinimizar});

  /// A aba aberta (0 Início · 1 Conversas · 2 NN News · 3 Avisos).
  static final aba = ValueNotifier<int>(0);

  /// Pedido de abrir uma conversa (notificação tocada, atalho do painel).
  static final conversaPedida = ValueNotifier<int?>(null);

  static void irPara(int i) => aba.value = i;

  static void abrirConversa(int id) {
    if (id <= 0) return;
    aba.value = 1;
    conversaPedida.value = id;
  }

  @override
  State<Casca> createState() => _CascaState();
}

class _CascaState extends State<Casca> {
  Controle get c => widget.c;

  @override
  void initState() {
    super.initState();
    Casca.aba.addListener(_mudou);
    c.addListener(_mudou);
    widget.atualizador.addListener(_mudou);
  }

  @override
  void dispose() {
    Casca.aba.removeListener(_mudou);
    c.removeListener(_mudou);
    widget.atualizador.removeListener(_mudou);
    super.dispose();
  }

  void _mudou() {
    if (!mounted) return;
    // Sem comunicado na fila, a janela deixa de ficar por cima das outras.
    if (c.comunicados.isEmpty) unawaited(Janela.soltar());
    setState(() {});
  }

  Future<void> _minimizar() => widget.aoMinimizar();

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final aba = Casca.aba.value;
    final fundo = ((c.aparencia?['sazonal'] as Map?)?['fundo'])?.toString();
    return Scaffold(
      body: Stack(children: [
        Column(children: [
          _FaixaLogo(c),
          BarraOnda(
            fundo: fundo,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 2),
              child: Row(children: [
                LinkMenu(rotulo: 'Início', icone: Icons.home_outlined, ativo: aba == 0, onTap: () => Casca.irPara(0)),
                LinkMenu(rotulo: 'Conversas', icone: Icons.chat_bubble_outline_rounded, ativo: aba == 1, selo: c.naoLidas, onTap: () => Casca.irPara(1)),
                LinkMenu(
                    rotulo: ((c.aparencia?['news'] as Map?)?['nome'] ?? 'NN News').toString(),
                    icone: Icons.newspaper_outlined,
                    ativo: aba == 2,
                    onTap: () => Casca.irPara(2)),
                LinkMenu(rotulo: 'Avisos', icone: Icons.campaign_outlined, ativo: aba == 3, onTap: () => Casca.irPara(3)),
                const Spacer(),
                LinkMenu(rotulo: 'Minimizar', icone: Icons.minimize_rounded, ativo: false, onTap: _minimizar),
              ]),
            ),
          ),
          if (widget.atualizador.pronto != null) _FaixaAtualizacao(widget.atualizador),
          Expanded(
            child: IndexedStack(index: aba, children: [
              TelaInicio(c),
              TelaConversas(c, ativa: aba == 1),
              TelaNews(c, ativa: aba == 2),
              TelaAvisos(c, ativa: aba == 3),
            ]),
          ),
          RodapeApp(c.aparencia),
        ]),
        if (c.comunicados.isNotEmpty) _Comunicado(c, key: ValueKey(c.comunicados.first['id'])),
      ]),
      backgroundColor: p.bg,
    );
  }
}

/// A faixa de cima: a logo (a do tema sazonal, se houver) e, à direita, os ícones
/// do topo do site — Conversas, claro/escuro, status e o usuário.
class _FaixaLogo extends StatelessWidget {
  final Controle c;
  const _FaixaLogo(this.c);

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final eu = c.eu ?? const {};
    final st = (eu['status'] as Map?) ?? const {};
    final tam = switch ((c.aparencia?['logo_tam'] ?? '').toString()) { 'm' => 44.0, 'g' => 56.0, 'gg' => 72.0, _ => 34.0 };
    return Container(
      color: p.card,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
      child: Row(children: [
        LogoConecta(c, altura: tam),
        const SizedBox(width: 14),
        Text('Callcenter', style: TextStyle(color: p.muted, fontWeight: FontWeight.w600, letterSpacing: .2)),
        const Spacer(),
        _IconeTopo(
          tooltip: 'Conversas',
          icone: Icons.chat_bubble_outline_rounded,
          selo: c.naoLidas,
          onTap: () => Casca.irPara(1),
        ),
        const SizedBox(width: 6),
        _IconeTopo(
          tooltip: c.escuro ? 'Usar o modo claro' : 'Usar o modo escuro',
          icone: c.escuro ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
          onTap: () => c.definirModo(c.escuro ? 'claro' : 'escuro'),
        ),
        const SizedBox(width: 10),
        if (st.isNotEmpty) _SeletorStatus(c, st.cast<String, dynamic>()),
        const SizedBox(width: 10),
        _MenuUsuario(c),
      ]),
    );
  }
}

class _IconeTopo extends StatelessWidget {
  final String tooltip;
  final IconData icone;
  final int selo;
  final VoidCallback onTap;
  const _IconeTopo({required this.tooltip, required this.icone, required this.onTap, this.selo = 0});
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(99),
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(shape: BoxShape.circle, color: p.surface, border: Border.all(color: p.cardBorder)),
          child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
            Icon(icone, size: 20, color: p.primary),
            if (selo > 0) Positioned(top: -4, right: -6, child: Selo(selo)),
          ]),
        ),
      ),
    );
  }
}

const _statusRotulos = {
  'disponivel': 'Disponível',
  'reuniao': 'Em reunião',
  'ligacao': 'Em ligação',
  'almoco': 'Em almoço',
  'nao_perturbe': 'Não perturbe',
  'ausente': 'Ausente',
  'fora': 'Fora do expediente',
};

class _SeletorStatus extends StatelessWidget {
  final Controle c;
  final Map<String, dynamic> st;
  const _SeletorStatus(this.c, this.st);

  Future<void> _definir(BuildContext context, String status, {String mensagem = '', String duracao = 'hoje'}) async {
    try {
      await c.api.post('/v1/callapp/status', {'status': status, 'mensagem': mensagem, 'duracao': duracao});
      await c.atualizarEu();
    } catch (e) {
      if (context.mounted) avisar(context, erroDe(e), erro: true);
    }
  }

  Future<void> _dialogo(BuildContext context) async {
    Map<String, dynamic> dados;
    try {
      dados = ((await c.api.get('/v1/callapp/status')) as Map).cast<String, dynamic>();
    } catch (e) {
      if (context.mounted) avisar(context, erroDe(e), erro: true);
      return;
    }
    if (!context.mounted) return;
    var status = (st['escolhido'] ?? 'disponivel').toString();
    final msg = TextEditingController(text: (st['mensagem'] ?? '').toString());
    var duracao = 'hoje';
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: const Text('Status, mensagem e duração'),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              DropdownButtonFormField<String>(
                initialValue: status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: [
                  for (final o in (dados['opcoes'] as List? ?? const []))
                    DropdownMenuItem(value: o['codigo'].toString(), child: Row(children: [PontoStatus(o['codigo'].toString()), const SizedBox(width: 10), Text(o['rotulo'].toString())])),
                ],
                onChanged: (v) => set(() => status = v ?? status),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: msg,
                maxLength: (dados['max_msg'] as num?)?.toInt() ?? 80,
                decoration: const InputDecoration(labelText: 'Mensagem (opcional)', hintText: 'volto às 14h'),
              ),
              DropdownButtonFormField<String>(
                initialValue: duracao,
                decoration: const InputDecoration(labelText: 'Limpar depois de'),
                items: [
                  for (final o in (dados['duracoes'] as List? ?? const []))
                    DropdownMenuItem(value: o['chave'].toString(), child: Text(o['rotulo'].toString())),
                ],
                onChanged: (v) => set(() => duracao = v ?? duracao),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Salvar')),
          ],
        ),
      ),
    );
    if (ok == true && context.mounted) await _definir(context, status, mensagem: msg.text, duracao: duracao);
    msg.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final escolhido = (st['escolhido'] ?? 'disponivel').toString();
    return PopupMenuButton<String>(
      tooltip: 'Seu status',
      position: PopupMenuPosition.under,
      onSelected: (v) => v == '_mais' ? _dialogo(context) : _definir(context, v),
      itemBuilder: (_) => [
        for (final e in _statusRotulos.entries)
          PopupMenuItem(value: e.key, child: Row(children: [PontoStatus(e.key), const SizedBox(width: 10), Text(e.value), if (e.key == escolhido) ...[const Spacer(), Icon(Icons.check, size: 18, color: p.primary)]])),
        const PopupMenuDivider(),
        const PopupMenuItem(value: '_mais', child: Text('Mensagem e duração…')),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(99), border: Border.all(color: p.cardBorder)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          PontoStatus(escolhido),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 230),
            child: Text((st['mensagem'] ?? '').toString().isNotEmpty ? '${_statusRotulos[escolhido] ?? ''} — ${st['mensagem']}' : (_statusRotulos[escolhido] ?? ''),
                overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
          ),
          const Icon(Icons.expand_more_rounded, size: 18),
        ]),
      ),
    );
  }
}

class _MenuUsuario extends StatelessWidget {
  final Controle c;
  const _MenuUsuario(this.c);

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final eu = c.eu ?? const {};
    return PopupMenuButton<String>(
      tooltip: 'Sua conta',
      position: PopupMenuPosition.under,
      onSelected: (v) async {
        switch (v) {
          case 'som':
            Som.ligado = !Som.ligado;
            c.arm.definir('som_mensagem', Som.ligado);
          case 'inicio':
            final ativo = await InicioComSistema.ativo();
            final r = await InicioComSistema.definir(!ativo);
            if (context.mounted) avisar(context, r ?? (!ativo ? 'O app vai abrir junto com o computador.' : 'O app não abre mais sozinho.'));
          case 'sobre':
            if (!context.mounted) return;
            showAboutDialog(context: context, applicationName: AppConfig.nome, applicationVersion: AppConfig.versao,
                children: [Text('Computador: ${(eu['computador'] as Map?)?['nome'] ?? c.nomeComputador}')]);
          case 'sair':
            final ok = await showDialog<bool>(
              context: context,
              builder: (d) => AlertDialog(
                title: const Text('Sair da conta?'),
                content: const Text('O app volta para a tela de login. Para entrar de novo, use o e-mail e a senha.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancelar')),
                  FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Sair da conta')),
                ],
              ),
            );
            if (ok == true) await c.sair();
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(enabled: false, child: Text((eu['email'] ?? '').toString(), style: TextStyle(color: p.muted, fontSize: 12.5))),
        CheckedPopupMenuItem(value: 'som', checked: Som.ligado, child: const Text('Som de mensagem nova')),
        const PopupMenuItem(value: 'inicio', child: Text('Abrir junto com o computador (liga/desliga)')),
        const PopupMenuItem(value: 'sobre', child: Text('Sobre o app')),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'sair', child: Text('Sair da conta')),
      ],
      child: Container(
        padding: const EdgeInsets.fromLTRB(3, 3, 12, 3),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(99), border: Border.all(color: p.cardBorder)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Avatar(url: eu['avatar']?.toString(), nome: (eu['nome'] ?? '').toString(), tam: 32),
          const SizedBox(width: 8),
          Text(c.primeiroNome, style: const TextStyle(fontWeight: FontWeight.w600)),
          const Icon(Icons.expand_more_rounded, size: 18),
        ]),
      ),
    );
  }
}

class _FaixaAtualizacao extends StatelessWidget {
  final Atualizador a;
  const _FaixaAtualizacao(this.a);
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      margin: const EdgeInsets.fromLTRB(22, 4, 22, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(color: p.success.withValues(alpha: .12), borderRadius: BorderRadius.circular(10), border: Border.all(color: p.success.withValues(alpha: .4))),
      child: Row(children: [
        Icon(Icons.system_update_alt_rounded, color: p.success, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text('A versão ${a.versaoNova} está pronta. Ela é instalada quando o app for para a bandeja — ou agora.')),
        TextButton(onPressed: a.instalar, child: const Text('Atualizar agora')),
      ]),
    );
  }
}

/// O comunicado: por cima de tudo, até o "Entendi". Vários = um por vez.
class _Comunicado extends StatelessWidget {
  final Controle c;
  const _Comunicado(this.c, {super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final fila = c.comunicados;
    final atual = fila.first;
    final id = (atual['id'] as num).toInt();
    final ultimo = fila.length == 1;
    return Positioned.fill(
      child: Focus(
        autofocus: true,
        onKeyEvent: (_, ev) {
          if (ev is KeyDownEvent && (ev.logicalKey == LogicalKeyboardKey.escape || ev.logicalKey == LogicalKeyboardKey.enter)) {
            c.comunicadoVisto(id);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Container(
          color: Colors.black.withValues(alpha: .55),
          alignment: Alignment.center,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620, maxHeight: 620),
            child: Material(
              color: p.card,
              borderRadius: BorderRadius.circular(18),
              clipBehavior: Clip.antiAlias,
              elevation: 18,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(26, 22, 26, 18),
                  decoration: BoxDecoration(gradient: LinearGradient(colors: [p.topoIni, p.topoFim])),
                  child: Row(children: [
                    const Icon(Icons.campaign_rounded, color: Colors.white, size: 26),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text((atual['titulo'] ?? 'Comunicado').toString(),
                          style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                    ),
                    if (fila.length > 1)
                      Text('1 de ${fila.length}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  ]),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(26, 20, 26, 8),
                    child: TextoComLinks((atual['mensagem'] ?? '').toString(), estilo: TextStyle(fontSize: 16, height: 1.5, color: p.text)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(26, 8, 26, 22),
                  child: Row(children: [
                    Expanded(
                      child: Text([if ((atual['autor'] ?? '').toString().isNotEmpty) atual['autor'], atual['quando']].whereType<Object>().join(' · '),
                          style: TextStyle(color: p.muted, fontSize: 13)),
                    ),
                    FilledButton(onPressed: () => c.comunicadoVisto(id), child: Text(ultimo ? 'Entendi' : 'Entendi — próximo')),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
