// "Versão X disponível — Atualizar agora": o mesmo painel na Visão geral e em
// Configurações → Sobre. Mostra o download, o erro e, no Linux, o "Baixar".
import 'package:flutter/material.dart';

import '../servicos/controle.dart';
import '../tema.dart';
import 'cabecalho.dart' show bytesTexto;

class PainelAtualizacao extends StatelessWidget {
  final Controle c;
  const PainelAtualizacao(this.c, {super.key});

  @override
  Widget build(BuildContext context) {
    final a = c.atualizacao;
    if (a == null && c.erroAtualizacao == null) return const SizedBox.shrink();
    final versao = a?['versao'] as String? ?? '';
    final tamanho = (a?['tamanho'] as num?)?.toInt() ?? 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.system_update_alt, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(versao.isEmpty ? 'Atualização do NN Cloud' : 'Versão $versao disponível',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
          ]),
          const SizedBox(height: 8),
          if (c.atualizando) ...[
            LinearProgressIndicator(value: c.progressoAtualizacao),
            const SizedBox(height: 8),
            Text(
              c.progressoAtualizacao != null
                  ? 'Baixando a versão nova… ${(c.progressoAtualizacao! * 100).round()}%'
                  : 'Preparando a instalação. O NN Cloud fecha e abre de novo sozinho.',
              style: TextStyle(color: Cores.fraco(context)),
            ),
          ] else ...[
            Text(
              c.atualizaAqui
                  ? 'O NN Cloud fecha por alguns segundos, instala a versão nova e abre de novo. Nada do que está sincronizado se perde.'
                  : 'Baixe o instalador e abra-o para atualizar (é preciso a senha de administrador).',
              style: TextStyle(color: Cores.fraco(context)),
            ),
            if (c.erroAtualizacao != null) ...[
              const SizedBox(height: 8),
              Text(c.erroAtualizacao!, style: TextStyle(color: Cores.situacao(context, 'erro'))),
            ],
            if (a != null) ...[
              const SizedBox(height: 12),
              Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
                FilledButton.icon(
                  onPressed: c.atualizarAgora,
                  icon: Icon(c.atualizaAqui ? Icons.system_update_alt : Icons.download),
                  label: Text(c.atualizaAqui ? 'Atualizar agora' : 'Baixar'),
                ),
                if (c.atualizaAqui)
                  TextButton(onPressed: () => c.abrirNavegador(c.urlDownload), child: const Text('Baixar o instalador')),
                if (tamanho > 0) Text(bytesTexto(tamanho), style: TextStyle(color: Cores.fraco(context), fontSize: 12.5)),
              ]),
            ],
          ],
        ]),
      ),
    );
  }
}
