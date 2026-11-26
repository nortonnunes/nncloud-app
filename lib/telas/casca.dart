// A casca da sessão: o topo igual ao do NN Conecta — a faixa da logo (com a
// imagem do tema sazonal, quando há) e os ícones do app à direita, inclusive o
// Minimizar; embaixo, a barra do menu em onda, na cor do tema escolhido lá
// (Início · Conversas · Atendimento · NN News · Avisos + a busca do devedor) —,
// o conteúdo e, por cima de tudo, o COMUNICADO (que só sai com "Entendi").
// Versão nova publicada: um aviso (uma vez por versão) e o botão "Atualizar".
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

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
import 'atendimento/atendimento.dart';
import 'atendimento/busca_topo.dart';
import 'avisos.dart';
import 'conversas/conversas.dart';
import 'inicio.dart';
import 'news.dart';

class Casca extends StatefulWidget {
  final Controle c;
  final Atualizador atualizador;
  final Future<void> Function() aoMinimizar;
  const Casca(this.c, this.atualizador, {super.key, required this.aoMinimizar});

  /// A aba aberta (0 Início · 1 Conversas · 2 NN News · 3 Avisos · 4 Atendimento).
  /// ⚠️ Os números são FIXOS (notificações e atalhos pulam por eles); a ORDEM do
  /// menu é outra coisa — o Atendimento aparece depois de Conversas.
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
  Atualizador get a => widget.atualizador;

  /// A versão já avisada nesta sessão (o aviso sai uma vez por versão).
  String? _versaoAvisada;
  bool _dialogoAberto = false;

  @override
  void initState() {
    super.initState();
    Casca.aba.addListener(_mudou);
    c.addListener(_mudou);
    a.addListener(_mudou);
    WidgetsBinding.instance.addPostFrameCallback((_) => _talvezAvisarVersao());
  }

  @override
  void dispose() {
    Casca.aba.removeListener(_mudou);
    c.removeListener(_mudou);
    a.removeListener(_mudou);
    super.dispose();
  }

  void _mudou() {
    if (!mounted) return;
    // Sem comunicado na fila, a janela deixa de ficar por cima das outras.
    if (c.comunicados.isEmpty) unawaited(Janela.soltar());
    setState(() {});
    _talvezAvisarVersao();
  }

  /// Versão nova publicada no NN Conecta: o aviso abre UMA vez por versão — e
  /// espera o comunicado, que tem prioridade.
  void _talvezAvisarVersao() {
    final v = a.versaoNova;
    if (v == null ||
        v == _versaoAvisada ||
        _dialogoAberto ||
        c.comunicados.isNotEmpty) {
      return;
    }
    _versaoAvisada = v;
    WidgetsBinding.instance.addPostFrameCallback((_) => _abrirAtualizacao());
  }

  Future<void> _abrirAtualizacao() async {
    if (!mounted || _dialogoAberto) return;
    _dialogoAberto = true;
    try {
      await showDialog<void>(
          context: context, builder: (_) => DialogoAtualizacao(a));
    } finally {
      _dialogoAberto = false;
    }
  }

  Future<void> _minimizar() => widget.aoMinimizar();

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final aba = Casca.aba.value;
    return Scaffold(
      body: Stack(children: [
        Column(children: [
          FaixaTopo(c, a,
              aoMinimizar: _minimizar, aoAtualizar: _abrirAtualizacao),
          BarraOnda(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
              child: LayoutBuilder(builder: (_, cons) {
                final links = Row(mainAxisSize: MainAxisSize.min, children: [
                  LinkMenu(
                      rotulo: 'Início',
                      ativo: aba == 0,
                      onTap: () => Casca.irPara(0)),
                  LinkMenu(
                      rotulo: 'Conversas',
                      ativo: aba == 1,
                      selo: c.naoLidas,
                      onTap: () => Casca.irPara(1)),
                  LinkMenu(
                      rotulo: 'Atendimento',
                      ativo: aba == 4,
                      onTap: () => Casca.irPara(4)),
                  LinkMenu(
                      rotulo:
                          ((c.aparencia?['news'] as Map?)?['nome'] ?? 'NN News')
                              .toString(),
                      ativo: aba == 2,
                      onTap: () => Casca.irPara(2)),
                  LinkMenu(
                      rotulo: 'Avisos',
                      ativo: aba == 3,
                      onTap: () => Casca.irPara(3)),
                ]);
                final busca =
                    BuscaDevedor(c, irParaAtendimento: () => Casca.irPara(4));
                // Como no site: o menu CENTRALIZADO na barra. Em tela estreita
                // ele centraliza no espaço que a busca deixa (não passa por baixo dela).
                if (cons.maxWidth >= 1320) {
                  return SizedBox(
                    height: 40,
                    child: Stack(alignment: Alignment.center, children: [
                      Center(child: links),
                      Align(alignment: Alignment.centerRight, child: busca),
                    ]),
                  );
                }
                return Row(children: [
                  Expanded(child: Center(child: links)),
                  const SizedBox(width: 12),
                  busca
                ]);
              }),
            ),
          ),
          Expanded(
            child: IndexedStack(index: aba, children: [
              TelaInicio(c),
              TelaConversas(c, ativa: aba == 1),
              TelaNews(c, ativa: aba == 2),
              TelaAvisos(c, ativa: aba == 3),
              TelaAtendimento(c),
            ]),
          ),
          RodapeApp(c.aparencia),
        ]),
        if (c.comunicados.isNotEmpty)
          _Comunicado(c, key: ValueKey(c.comunicados.first['id'])),
      ]),
      backgroundColor: p.bg,
    );
  }
}

/// A faixa de cima, igual à do site (`.topstrip`): a logo à esquerda e, à direita,
/// os ícones DO APP — Atualizar (com versão nova), Conversas, claro/escuro, status,
/// o usuário e o Minimizar. Com tema sazonal que tem imagem do topo, a imagem é o
/// fundo da faixa (`cover`, centralizada, como no site) e a faixa ganha a altura
/// da imagem; os ícones sobem para o alto, acima da arte.
class FaixaTopo extends StatefulWidget {
  final Controle c;
  final Atualizador a;
  final Future<void> Function() aoMinimizar;
  final Future<void> Function() aoAtualizar;
  const FaixaTopo(this.c, this.a,
      {super.key, required this.aoMinimizar, required this.aoAtualizar});

  /// A faixa com imagem tem a proporção dela, dentro destes limites.
  static const double alturaMaxima = 190;

  /// De onde vem a imagem do topo (os testes trocam por uma imagem local).
  static ImageProvider Function(String url) imagem = NetworkImage.new;

  @override
  State<FaixaTopo> createState() => _FaixaTopoState();
}

class _FaixaTopoState extends State<FaixaTopo> {
  String? _url;
  double? _proporcao;
  ImageStream? _stream;
  ImageStreamListener? _ouvinte;

  /// Lê a largura/altura da imagem do topo, para a faixa ter a proporção dela.
  void _resolver(String? url) {
    if (url == _url) return;
    if (_stream != null && _ouvinte != null) _stream!.removeListener(_ouvinte!);
    _url = url;
    _proporcao = null;
    _stream = null;
    if (url == null) return;
    _ouvinte = ImageStreamListener((info, _) {
      final w = info.image.width, h = info.image.height;
      if (mounted && h > 0 && url == _url) setState(() => _proporcao = w / h);
    }, onError: (_, __) {});
    _stream = FaixaTopo.imagem(url).resolve(ImageConfiguration.empty)
      ..addListener(_ouvinte!);
  }

  @override
  void dispose() {
    if (_stream != null && _ouvinte != null) _stream!.removeListener(_ouvinte!);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final p = context.pal;
    final eu = c.eu ?? const {};
    final st = (eu['status'] as Map?) ?? const {};
    final tam = switch ((c.aparencia?['logo_tam'] ?? '').toString()) {
      'm' => 44.0,
      'g' => 56.0,
      'gg' => 72.0,
      _ => 34.0
    };
    final fundoUrl = ((c.aparencia?['sazonal'] as Map?)?['fundo'])?.toString();
    final fundo = (fundoUrl ?? '').isEmpty ? null : fundoUrl;
    _resolver(fundo);

    final direita = Row(mainAxisSize: MainAxisSize.min, children: [
      if (widget.a.temVersaoNova) ...[
        BotaoAtualizar(widget.a, onTap: widget.aoAtualizar),
        const SizedBox(width: 10)
      ],
      IconeTopo(
          tooltip: 'Conversas',
          icone: Icons.chat_bubble_outline_rounded,
          selo: c.naoLidas,
          onTap: () => Casca.irPara(1)),
      const SizedBox(width: 8),
      IconeTopo(
        tooltip: c.escuro ? 'Usar o modo claro' : 'Usar o modo escuro',
        icone: c.escuro ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
        onTap: () => c.definirModo(c.escuro ? 'claro' : 'escuro'),
      ),
      const SizedBox(width: 10),
      if (st.isNotEmpty) ...[
        _SeletorStatus(c, st.cast<String, dynamic>()),
        const SizedBox(width: 10)
      ],
      _MenuUsuario(c),
      const SizedBox(width: 10),
      IconeTopo(
          tooltip: 'Minimizar — o app continua no ícone ao lado do relógio',
          icone: Icons.remove_rounded,
          onTap: widget.aoMinimizar),
    ]);

    return LayoutBuilder(builder: (_, cons) {
      final base = math.max(tam + 24, 64.0);
      final double altura = fundo == null
          ? base
          : (cons.maxWidth / (_proporcao ?? 1920 / 250))
              .clamp(base, math.max(base, FaixaTopo.alturaMaxima))
              .toDouble();
      return Container(
        height: altura,
        decoration: BoxDecoration(
          color: p.card,
          border: Border(bottom: BorderSide(color: p.cardBorder)),
          image: fundo == null
              ? null
              : DecorationImage(
                  image: FaixaTopo.imagem(fundo),
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                  onError: (_, __) {}),
        ),
        padding: EdgeInsets.fromLTRB(22, fundo == null ? 0 : 12, 22, 0),
        child: Row(
            crossAxisAlignment: fundo == null
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              LogoConecta(c, altura: tam),
              const Spacer(),
              direita,
            ]),
      );
    });
  }
}

/// Um ícone redondo da faixa de cima (o `.conversas-link` do site).
class IconeTopo extends StatelessWidget {
  final String tooltip;
  final IconData icone;
  final int selo;
  final VoidCallback onTap;
  const IconeTopo(
      {super.key,
      required this.tooltip,
      required this.icone,
      required this.onTap,
      this.selo = 0});
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: p.surface,
        shape: CircleBorder(side: BorderSide(color: p.cardBorder)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  Icon(icone, size: 20, color: p.primary),
                  if (selo > 0)
                    Positioned(top: -4, right: -6, child: Selo(selo)),
                ]),
          ),
        ),
      ),
    );
  }
}

/// O verde dos botões com texto branco (o `#0f7a46` do softphone: 5,4:1 — o verde
/// do ponto de status reprovaria como fundo de texto).
const _verdeBotao = Color(0xFF0F7A46);

/// O botão "Atualizar" da faixa de cima: aparece assim que o NN Conecta publica
/// uma versão maior e fica até ela ser instalada. O clique abre o aviso.
class BotaoAtualizar extends StatelessWidget {
  final Atualizador a;
  final VoidCallback onTap;
  const BotaoAtualizar(this.a, {super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final (IconData icone, String texto) = a.instalando
        ? (Icons.hourglass_top_rounded, 'Instalando…')
        : a.baixando
            ? (
                Icons.downloading_rounded,
                'Baixando ${(a.progresso * 100).clamp(0, 100).round()}%'
              )
            : a.manual
                ? (Icons.install_desktop_rounded, 'Instalar a ${a.versaoNova}')
                : a.pronto == null && a.erro != null
                    ? (Icons.refresh_rounded, 'Atualização: tentar de novo')
                    : (
                        Icons.system_update_alt_rounded,
                        'Atualizar para a ${a.versaoNova}'
                      );
    return Tooltip(
      message: 'A versão ${a.versaoNova} do ${AppConfig.nome} foi publicada',
      child: Material(
        color: _verdeBotao,
        borderRadius: BorderRadius.circular(99),
        child: InkWell(
          borderRadius: BorderRadius.circular(99),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icone, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text(texto,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// O aviso de versão nova (abre sozinho uma vez por versão, e pelo botão do topo).
class DialogoAtualizacao extends StatelessWidget {
  final Atualizador a;
  const DialogoAtualizacao(this.a, {super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: a,
      builder: (context, _) {
        final p = context.pal;
        final v = a.versaoNova ?? '';
        final linhas = <Widget>[
          Text(
              'A versão $v foi publicada no NN Conecta. Este computador está na ${AppConfig.versao}.',
              style: const TextStyle(fontSize: 15)),
          const SizedBox(height: 12),
        ];
        if (a.instalando) {
          linhas.add(Text(
              'Instalando… o app fecha e abre de novo sozinho em alguns segundos.',
              style: TextStyle(color: p.muted)));
        } else if (a.baixando) {
          linhas.addAll([
            LinearProgressIndicator(
                value: a.progresso > 0 ? a.progresso : null,
                minHeight: 6,
                borderRadius: BorderRadius.circular(99)),
            const SizedBox(height: 8),
            Text(
                'Baixando a versão nova… ${(a.progresso * 100).clamp(0, 100).round()}%',
                style: TextStyle(color: p.muted)),
          ]);
        } else if (a.manual) {
          linhas.addAll([
            if (a.erro != null) ...[
              Text(a.erro!,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8)
            ],
            Text(
                Platform.isMacOS
                    ? 'Clique em "Abrir o instalador", arraste o app para a pasta Aplicativos (substituindo o atual) e abra-o de lá.'
                    : 'Clique em "Abrir o instalador" e conclua a instalação na janela do sistema.',
                style: TextStyle(color: p.muted)),
          ]);
        } else if (a.pronto == null && a.erro != null) {
          linhas.add(Text(a.erro!,
              style: TextStyle(color: p.danger, fontWeight: FontWeight.w600)));
        } else {
          linhas.add(Text(
              a.pronto != null
                  ? 'Pronta para instalar. Ao clicar em "Atualizar agora", o app fecha e abre de novo em alguns segundos — termine antes o atendimento em curso.'
                  : 'Ao clicar em "Atualizar agora", a versão nova é baixada e o app fecha e abre de novo em alguns segundos.',
              style: TextStyle(color: p.muted)));
          linhas.addAll([
            const SizedBox(height: 8),
            Text(
                'Se preferir, minimize o app: ele se atualiza sozinho enquanto está no ícone ao lado do relógio.',
                style: TextStyle(color: p.muted, fontSize: 13)),
          ]);
        }
        return AlertDialog(
          icon: Icon(Icons.system_update_alt_rounded,
              color: _verdeBotao, size: 30),
          title: const Text('Nova versão do Conecta Callcenter'),
          content: SizedBox(
              width: 460,
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: linhas)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Depois')),
            if (a.manual)
              FilledButton(
                  onPressed: a.abrirInstalador,
                  child: const Text('Abrir o instalador'))
            else
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: _verdeBotao,
                    foregroundColor: Colors.white),
                onPressed: a.instalando ? null : a.atualizarAgora,
                child: Text(a.pronto == null && a.erro != null && !a.baixando
                    ? 'Tentar de novo'
                    : 'Atualizar agora'),
              ),
          ],
        );
      },
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

  Future<void> _definir(BuildContext context, String status,
      {String mensagem = '', String duracao = 'hoje'}) async {
    try {
      await c.api.post('/v1/callapp/status',
          {'status': status, 'mensagem': mensagem, 'duracao': duracao});
      await c.atualizarEu();
    } catch (e) {
      if (context.mounted) avisar(context, erroDe(e), erro: true);
    }
  }

  Future<void> _dialogo(BuildContext context) async {
    Map<String, dynamic> dados;
    try {
      dados = ((await c.api.get('/v1/callapp/status')) as Map)
          .cast<String, dynamic>();
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
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: status,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: [
                      for (final o in (dados['opcoes'] as List? ?? const []))
                        DropdownMenuItem(
                            value: o['codigo'].toString(),
                            child: Row(children: [
                              PontoStatus(o['codigo'].toString()),
                              const SizedBox(width: 10),
                              Text(o['rotulo'].toString())
                            ])),
                    ],
                    onChanged: (v) => set(() => status = v ?? status),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: msg,
                    maxLength: (dados['max_msg'] as num?)?.toInt() ?? 80,
                    decoration: const InputDecoration(
                        labelText: 'Mensagem (opcional)',
                        hintText: 'volto às 14h'),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: duracao,
                    decoration:
                        const InputDecoration(labelText: 'Limpar depois de'),
                    items: [
                      for (final o in (dados['duracoes'] as List? ?? const []))
                        DropdownMenuItem(
                            value: o['chave'].toString(),
                            child: Text(o['rotulo'].toString())),
                    ],
                    onChanged: (v) => set(() => duracao = v ?? duracao),
                  ),
                ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(d, false),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () => Navigator.pop(d, true),
                child: const Text('Salvar')),
          ],
        ),
      ),
    );
    if (ok == true && context.mounted) {
      await _definir(context, status, mensagem: msg.text, duracao: duracao);
    }
    msg.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final escolhido = (st['escolhido'] ?? 'disponivel').toString();
    return PopupMenuButton<String>(
      tooltip: 'Seu status',
      position: PopupMenuPosition.under,
      onSelected: (v) =>
          v == '_mais' ? _dialogo(context) : _definir(context, v),
      itemBuilder: (_) => [
        for (final e in _statusRotulos.entries)
          PopupMenuItem(
              value: e.key,
              child: Row(children: [
                PontoStatus(e.key),
                const SizedBox(width: 10),
                Text(e.value),
                if (e.key == escolhido) ...[
                  const Spacer(),
                  Icon(Icons.check, size: 18, color: p.primary)
                ]
              ])),
        const PopupMenuDivider(),
        const PopupMenuItem(value: '_mais', child: Text('Mensagem e duração…')),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: p.cardBorder)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          PontoStatus(escolhido),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 230),
            child: Text(
                (st['mensagem'] ?? '').toString().isNotEmpty
                    ? '${_statusRotulos[escolhido] ?? ''} — ${st['mensagem']}'
                    : (_statusRotulos[escolhido] ?? ''),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13.5)),
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
            if (context.mounted) {
              avisar(
                  context,
                  r ??
                      (!ativo
                          ? 'O app vai abrir junto com o computador.'
                          : 'O app não abre mais sozinho.'));
            }
          case 'sobre':
            if (!context.mounted) return;
            showAboutDialog(
                context: context,
                applicationName: AppConfig.nome,
                applicationVersion: AppConfig.versao,
                children: [
                  Text(
                      'Computador: ${(eu['computador'] as Map?)?['nome'] ?? c.nomeComputador}')
                ]);
          case 'sair':
            final ok = await showDialog<bool>(
              context: context,
              builder: (d) => AlertDialog(
                title: const Text('Sair da conta?'),
                content: const Text(
                    'O app volta para a tela de login. Para entrar de novo, use o e-mail e a senha.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(d, false),
                      child: const Text('Cancelar')),
                  FilledButton(
                      onPressed: () => Navigator.pop(d, true),
                      child: const Text('Sair da conta')),
                ],
              ),
            );
            if (ok == true) await c.sair();
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
            enabled: false,
            child: Text((eu['email'] ?? '').toString(),
                style: TextStyle(color: p.muted, fontSize: 12.5))),
        CheckedPopupMenuItem(
            value: 'som',
            checked: Som.ligado,
            child: const Text('Som de mensagem nova')),
        const PopupMenuItem(
            value: 'inicio',
            child: Text('Abrir junto com o computador (liga/desliga)')),
        const PopupMenuItem(value: 'sobre', child: Text('Sobre o app')),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'sair', child: Text('Sair da conta')),
      ],
      child: Container(
        padding: const EdgeInsets.fromLTRB(3, 3, 12, 3),
        // Fundo do cartão: sobre a imagem do tema sazonal, o nome precisa de chão.
        decoration: BoxDecoration(
            color: p.card,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: p.cardBorder)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Avatar(
              url: eu['avatar']?.toString(),
              nome: (eu['nome'] ?? '').toString(),
              tam: 32),
          const SizedBox(width: 8),
          Text(c.primeiroNome,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          const Icon(Icons.expand_more_rounded, size: 18),
        ]),
      ),
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
          if (ev is KeyDownEvent &&
              (ev.logicalKey == LogicalKeyboardKey.escape ||
                  ev.logicalKey == LogicalKeyboardKey.enter)) {
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
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.fromLTRB(26, 22, 26, 18),
                      decoration: BoxDecoration(
                          gradient:
                              LinearGradient(colors: [p.topoIni, p.topoFim])),
                      child: Row(children: [
                        const Icon(Icons.campaign_rounded,
                            color: Colors.white, size: 26),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                              (atual['titulo'] ?? 'Comunicado').toString(),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800)),
                        ),
                        if (fila.length > 1)
                          Text('1 de ${fila.length}',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600)),
                      ]),
                    ),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(26, 20, 26, 8),
                        child: TextoComLinks(
                            (atual['mensagem'] ?? '').toString(),
                            estilo: TextStyle(
                                fontSize: 16, height: 1.5, color: p.text)),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(26, 8, 26, 22),
                      child: Row(children: [
                        Expanded(
                          child: Text(
                              [
                                if ((atual['autor'] ?? '')
                                    .toString()
                                    .isNotEmpty)
                                  atual['autor'],
                                atual['quando']
                              ].whereType<Object>().join(' · '),
                              style: TextStyle(color: p.muted, fontSize: 13)),
                        ),
                        FilledButton(
                            onPressed: () => c.comunicadoVisto(id),
                            child:
                                Text(ultimo ? 'Entendi' : 'Entendi — próximo')),
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
