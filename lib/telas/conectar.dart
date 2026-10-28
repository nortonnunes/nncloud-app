import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../servicos/controle.dart';
import '../tema.dart';
import '../widgets/cabecalho.dart';

/// Conectar este computador: o app mostra um código e abre o navegador; a
/// pessoa, já logada no NN Conecta (com 2FA), clica em Autorizar. O app nunca
/// vê a senha.
class TelaConectar extends StatelessWidget {
  final Controle c;
  const TelaConectar(this.c, {super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final esperando = c.codigo != null;
    return Scaffold(
      body: Column(children: [
        Cabecalho(
          altura: 190,
          filho: Row(children: [
            // Sobre o degradê azul o "NN" azul some: vai num selo branco.
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
              child: Image.asset('assets/icon.png', width: 46, height: 46),
            ),
            const SizedBox(width: 16),
            Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text('NN Cloud', style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
              Text('Suas pastas do computador sempre iguais às do NN Conecta',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 15)),
            ]),
          ]),
        ),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: esperando ? _codigo(context, cs) : _inicio(context, cs),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _inicio(BuildContext context, ColorScheme cs) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Conecte este computador', style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
        const SizedBox(height: 10),
        Text('Vamos abrir o NN Conecta no navegador. Entre com a sua conta, confira o código e clique em Autorizar.',
            textAlign: TextAlign.center, style: TextStyle(color: Cores.fraco(context), height: 1.4)),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: c.situacao == Situacao.conectando ? null : c.conectar,
          icon: const Icon(Icons.login),
          label: Text(c.situacao == Situacao.conectando ? 'Aguarde…' : 'Conectar ao NN Conecta'),
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
        ),
        if (c.mensagem != null) ...[
          const SizedBox(height: 16),
          Text(c.mensagem!, textAlign: TextAlign.center, style: TextStyle(color: Cores.situacao(context, 'erro'))),
        ],
      ]);

  Widget _codigo(BuildContext context, ColorScheme cs) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Confira este código no navegador', style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(14)),
          child: SelectableText(c.codigo!, textAlign: TextAlign.center,
              style: TextStyle(fontSize: 34, fontWeight: FontWeight.w700, letterSpacing: 4, color: cs.onPrimaryContainer)),
        ),
        const SizedBox(height: 14),
        Text('Depois de clicar em Autorizar, esta janela continua sozinha.', textAlign: TextAlign.center, style: TextStyle(color: Cores.fraco(context))),
        const SizedBox(height: 4),
        const LinearProgressIndicator(),
        const SizedBox(height: 18),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          TextButton.icon(onPressed: () => c.abrirNavegador(c.urlConectar!), icon: const Icon(Icons.open_in_browser), label: const Text('Abrir o navegador de novo')),
          TextButton.icon(
              onPressed: () => Clipboard.setData(ClipboardData(text: c.urlConectar!)), icon: const Icon(Icons.link), label: const Text('Copiar endereço')),
        ]),
        TextButton(onPressed: c.cancelarConexao, child: const Text('Cancelar')),
      ]);
}
