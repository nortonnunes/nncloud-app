// O aviso de mensagem nova DENTRO do app: um quadro no canto, abaixo do menu,
// quando o app está na frente mas a pessoa está noutra conversa ou noutra aba.
// Clicar abre a conversa; some sozinho em 8 s (o mouse em cima segura) e pelo X.
// Várias mensagens da mesma conversa viram um quadro só ("3 mensagens novas"),
// e no máximo três quadros ficam empilhados.
//
// E as escolhas da pessoa: menu da conta → "Avisos de mensagem nova".
import 'dart:async';

import 'package:flutter/material.dart';

import '../servicos/alertas.dart';
import '../tema.dart';
import '../widgets/comum.dart';

class QuadrosMensagem extends StatelessWidget {
  final Alertas alertas;
  final void Function(int conversa) aoAbrir;
  const QuadrosMensagem(this.alertas, {super.key, required this.aoAbrir});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<AvisoMensagem>>(
      valueListenable: alertas.quadros,
      builder: (_, lista, __) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final a in lista)
            Padding(
              key: ValueKey('quadro-${a.conversa}'),
              padding: const EdgeInsets.only(bottom: 10),
              child: QuadroMensagem(
                a,
                aoAbrir: () {
                  alertas.fecharQuadro(a.conversa);
                  if (a.conversa > 0) aoAbrir(a.conversa);
                },
                aoFechar: () => alertas.fecharQuadro(a.conversa),
              ),
            ),
        ],
      ),
    );
  }
}

class QuadroMensagem extends StatefulWidget {
  final AvisoMensagem a;
  final VoidCallback aoAbrir;
  final VoidCallback aoFechar;
  const QuadroMensagem(this.a, {super.key, required this.aoAbrir, required this.aoFechar});

  static const duracao = Duration(seconds: 8);

  @override
  State<QuadroMensagem> createState() => _QuadroMensagemState();
}

class _QuadroMensagemState extends State<QuadroMensagem> {
  Timer? _t;
  bool _sobre = false;

  @override
  void initState() {
    super.initState();
    _contar();
  }

  @override
  void didUpdateWidget(covariant QuadroMensagem old) {
    super.didUpdateWidget(old);
    // Chegou outra mensagem da mesma conversa: o tempo recomeça.
    if (widget.a.seq != old.a.seq) _contar();
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  void _contar() {
    _t?.cancel();
    if (_sobre) return;
    _t = Timer(QuadroMensagem.duracao, widget.aoFechar);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final a = widget.a;
    final semMovimento = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final linha2 = a.grupo && a.autor.isNotEmpty ? '${a.autor}: ${a.previa}' : a.previa;
    final quadro = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .14), blurRadius: 22, offset: const Offset(0, 8))],
      ),
      child: Material(
        color: p.card,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: widget.aoAbrir,
          child: Container(
            width: 360,
            padding: const EdgeInsets.fromLTRB(12, 12, 6, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: p.cardBorder),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Stack(clipBehavior: Clip.none, children: [
                a.conversa > 0
                    ? Avatar(url: a.avatar, nome: a.titulo, tam: 42)
                    : CircleAvatar(
                        radius: 21,
                        backgroundColor: p.primary.withValues(alpha: .14),
                        child: Icon(Icons.notifications_active_outlined, color: p.primary)),
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    width: 13,
                    height: 13,
                    decoration: BoxDecoration(color: const Color(0xFFE53935), shape: BoxShape.circle, border: Border.all(color: p.card, width: 2)),
                  ),
                ),
              ]),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Text(a.titulo,
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                    ),
                    if (a.quantas > 1)
                      Container(
                        margin: const EdgeInsets.only(left: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(color: p.primary, borderRadius: BorderRadius.circular(99)),
                        child: Text('${a.quantas} novas', style: TextStyle(color: p.card, fontSize: 11, fontWeight: FontWeight.w800)),
                      ),
                  ]),
                  const SizedBox(height: 3),
                  Text(linha2.isEmpty ? 'Nova mensagem' : linha2,
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 13, height: 1.3)),
                  if (a.conversa > 0) ...[
                    const SizedBox(height: 6),
                    Text('Clique para abrir a conversa', style: TextStyle(color: p.primary, fontSize: 12, fontWeight: FontWeight.w700)),
                  ],
                ]),
              ),
              IconButton(
                tooltip: 'Fechar o aviso',
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                onPressed: widget.aoFechar,
                icon: Icon(Icons.close_rounded, color: p.muted),
              ),
            ]),
          ),
        ),
      ),
    );
    return Semantics(
      liveRegion: true,
      label: 'Mensagem nova de ${a.titulo}',
      child: MouseRegion(
        onEnter: (_) {
          _sobre = true;
          _t?.cancel();
        },
        onExit: (_) {
          _sobre = false;
          _contar();
        },
        // Entra deslizando da direita (uma vez, ao aparecer).
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: semMovimento ? 1 : 0, end: 1),
          duration: semMovimento ? Duration.zero : const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: quadro,
          builder: (_, v, filho) => Opacity(
            opacity: v,
            child: FractionalTranslation(translation: Offset((1 - v) * .25, 0), child: filho),
          ),
        ),
      ),
    );
  }
}

/// Menu da conta → "Avisos de mensagem nova": som, quadro no canto, notificação.
class DialogoAvisos extends StatefulWidget {
  final Alertas alertas;
  const DialogoAvisos(this.alertas, {super.key});

  @override
  State<DialogoAvisos> createState() => _DialogoAvisosState();
}

class _DialogoAvisosState extends State<DialogoAvisos> {
  Alertas get al => widget.alertas;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return AlertDialog(
      title: const Text('Avisos de mensagem nova'),
      content: SizedBox(
        width: 460,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: al.som,
            onChanged: (v) => setState(() => al.definir(som: v)),
            title: const Text('Tocar um som'),
            subtitle: const Text('Um toque curto a cada mensagem nova.'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: al.quadro,
            onChanged: (v) => setState(() => al.definir(quadro: v)),
            title: const Text('Aviso no canto do app'),
            subtitle:
                const Text('Com o app na frente, quando você está em outra conversa ou em outra aba. Mostra quem escreveu e o começo da mensagem.'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: al.notificacao,
            onChanged: (v) => setState(() => al.definir(notificacao: v)),
            title: const Text('Notificação do sistema'),
            subtitle: const Text('Com o app minimizado ou atrás de outras janelas. Diz quem escreveu, sem o texto da mensagem.'),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.cardBorder)),
            child: Text(
              'O ícone ao lado do relógio ganha uma bolinha vermelha enquanto houver mensagem não lida — sempre, mesmo com os avisos desligados.\n'
              'Com o status "Não perturbe", o app não toca som nem mostra notificação.',
              style: TextStyle(color: p.muted, fontSize: 12.5, height: 1.4),
            ),
          ),
        ]),
      ),
      actions: [
        // Fecha antes: o quadro de teste aparece atrás desta janela.
        TextButton.icon(
          onPressed: al.algumLigado
              ? () {
                  Navigator.pop(context);
                  unawaited(al.testar());
                }
              : null,
          icon: const Icon(Icons.play_circle_outline_rounded),
          label: const Text('Testar'),
        ),
        FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar')),
      ],
    );
  }
}
