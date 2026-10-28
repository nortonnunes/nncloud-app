import 'package:flutter/material.dart';

import '../servicos/controle.dart';
import '../tema.dart';

/// O que ficou SÓ no computador (ou parou) e precisa da pessoa: nome que o
/// Windows não aceita, pasta só de leitura, espaço cheio, pasta sumida…
/// Nenhum problema apaga arquivo.
class TelaProblemas extends StatelessWidget {
  final Controle c;
  const TelaProblemas(this.c, {super.key});

  @override
  Widget build(BuildContext context) {
    final paradas = [
      for (final r in c.resultados.values)
        if (r.estado == 'erro' && r.mensagem != null) (c.pares.where((x) => x['id'] == r.par).firstOrNull?['nome'] ?? 'Pasta', r.mensagem!),
    ];
    final itens = [
      for (final r in c.resultados.values)
        for (final pr in r.problemas) (c.pares.where((x) => x['id'] == r.par).firstOrNull?['nome'] ?? 'Pasta', pr),
    ];
    return ListView(padding: const EdgeInsets.all(28), children: [
      Text('Problemas', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 6),
      Text('Nada aqui foi apagado: o arquivo continua no computador até o problema ser resolvido.', style: TextStyle(color: Cores.fraco(context))),
      const SizedBox(height: 18),
      if (paradas.isEmpty && itens.isEmpty)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Row(children: [
              Icon(Icons.check_circle_outline, color: Cores.situacao(context, 'ok'), size: 32),
              const SizedBox(width: 12),
              const Text('Nenhum problema. Tudo sincronizado.'),
            ]),
          ),
        ),
      for (final (nome, msg) in paradas)
        Card(
          child: ListTile(
            leading: Icon(Icons.pause_circle_outline, color: Cores.situacao(context, 'erro')),
            title: Text('$nome parou'),
            subtitle: Text(msg),
          ),
        ),
      if (itens.isNotEmpty) ...[
        const SizedBox(height: 12),
        Card(
          child: Column(children: [
            for (final (nome, msg) in itens)
              ListTile(
                dense: true,
                leading: Icon(Icons.report_gmailerrorred, color: Cores.situacao(context, 'alerta')),
                title: Text(msg.split(': ').first, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('$nome · ${msg.contains(': ') ? msg.substring(msg.indexOf(': ') + 2) : msg}'),
              ),
          ]),
        ),
      ],
    ]);
  }
}
