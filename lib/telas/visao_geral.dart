import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../servicos/controle.dart';
import '../tema.dart';
import '../widgets/cabecalho.dart';

/// (rótulo, cor-de-situação, ícone)
(String, String, IconData) rotuloSituacao(Situacao s) => switch (s) {
      Situacao.ok => ('Conectado', 'ok', Icons.cloud_done),
      Situacao.sincronizando => ('Sincronizando', 'ok', Icons.sync),
      Situacao.offline => ('Offline', 'alerta', Icons.cloud_off),
      Situacao.pausado => ('Pausado', 'neutro', Icons.pause_circle),
      Situacao.erro => ('Atenção', 'erro', Icons.error_outline),
      Situacao.conectando => ('Conectando', 'neutro', Icons.sync),
      Situacao.desconectado => ('Desconectado', 'erro', Icons.link_off),
    };

class TelaVisaoGeral extends StatelessWidget {
  final Controle c;
  final void Function(int) irPara;
  const TelaVisaoGeral(this.c, this.irPara, {super.key});

  @override
  Widget build(BuildContext context) {
    final eu = c.eu ?? {};
    final pessoa = (eu['pessoa'] as Map?) ?? {};
    final meu = (eu['meu_drive'] as Map?) ?? {};
    final usado = (meu['usado'] as int?) ?? 0, limite = (meu['limite'] as int?) ?? 0;
    final (rot, tipo, ico) = rotuloSituacao(c.situacao);
    return ListView(padding: EdgeInsets.zero, children: [
      Cabecalho(
        filho: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Olá, ${(pessoa['nome'] as String? ?? '').split(' ').first}',
                  style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('${pessoa['email'] ?? ''} · ${c.nomeComputador}', style: TextStyle(color: Colors.white.withValues(alpha: 0.88))),
              const SizedBox(height: 14),
              SizedBox(
                width: 320,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: limite > 0 ? (usado / limite).clamp(0, 1).toDouble() : 0,
                      minHeight: 7,
                      backgroundColor: Colors.white.withValues(alpha: 0.25),
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text('${bytesTexto(usado)} de ${bytesTexto(limite)} no Meu Drive', style: const TextStyle(color: Colors.white, fontSize: 13)),
                ]),
              ),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(ico, size: 16, color: Cores.situacao(context, tipo == 'neutro' ? 'neutro' : tipo)),
              const SizedBox(width: 6),
              Text(rot, style: TextStyle(fontWeight: FontWeight.w700, color: Cores.situacao(context, tipo))),
            ]),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(28, 4, 28, 28),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final ex in c.aguardando) _confirmacao(context, ex),
          if (c.mensagem != null && c.situacao != Situacao.ok && c.situacao != Situacao.sincronizando)
            _aviso(context, c.mensagem!, c.situacao == Situacao.offline ? 'alerta' : 'erro'),
          Wrap(spacing: 14, runSpacing: 14, children: [
            _cartao(context, Icons.description_outlined, 'Arquivos', NumberFormat.decimalPattern('pt_BR').format(c.arquivosSincronizados),
                'sincronizados'),
            _cartao(context, Icons.folder_outlined, 'Pastas', '${c.pares.length}', 'neste computador', aoTocar: () => irPara(1)),
            _cartao(context, Icons.pending_actions, 'Pendentes', '${c.pendentes + c.problemas.length}', 'precisam de atenção',
                aoTocar: () => irPara(3)),
          ]),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(c.situacao == Situacao.sincronizando ? 'Sincronizando arquivos' : 'Sincronização',
                      style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  if (c.ultimoSync != null)
                    Text('última às ${DateFormat.Hm().format(c.ultimoSync!)}', style: TextStyle(color: Cores.fraco(context), fontSize: 12.5)),
                ]),
                const SizedBox(height: 12),
                if (c.situacao == Situacao.sincronizando) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: 8),
                  Text(c.arquivoAtual != null ? c.arquivoAtual! : 'Conferindo as pastas…',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Cores.fraco(context))),
                  Text('${c.arquivosCiclo} arquivo(s) · ${bytesTexto(c.bytesCiclo)} transferidos neste ciclo',
                      style: TextStyle(color: Cores.fraco(context), fontSize: 12.5)),
                ] else
                  Text(c.pares.isEmpty ? 'Nenhuma pasta sincronizada ainda.' : 'Tudo em dia.', style: TextStyle(color: Cores.fraco(context))),
                const SizedBox(height: 14),
                Wrap(spacing: 10, runSpacing: 10, children: [
                  FilledButton.icon(
                    onPressed: c.pares.isEmpty || c.situacao == Situacao.sincronizando ? null : c.sincronizarAgora,
                    icon: const Icon(Icons.sync),
                    label: const Text('Sincronizar agora'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => c.pausar(!c.pausado),
                    icon: Icon(c.pausado ? Icons.play_arrow : Icons.pause),
                    label: Text(c.pausado ? 'Retomar' : 'Pausar'),
                  ),
                  if (c.pares.isEmpty)
                    OutlinedButton.icon(onPressed: () => irPara(1), icon: const Icon(Icons.create_new_folder_outlined), label: const Text('Adicionar pasta')),
                ]),
              ]),
            ),
          ),
          const SizedBox(height: 20),
          Text('Atividade recente', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (c.atividade.isEmpty)
            Text('Nada por aqui ainda.', style: TextStyle(color: Cores.fraco(context)))
          else
            Card(
              child: Column(children: [
                for (final a in c.atividade.take(8))
                  ListTile(
                    dense: true,
                    leading: Icon(_icone(a.tipo), color: Cores.situacao(context, a.tipo == 'erro' ? 'erro' : (a.tipo == 'conflito' ? 'alerta' : 'neutro'))),
                    title: Text(a.caminho.isEmpty ? (a.detalhe ?? '') : a.caminho, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${_rotulo(a.tipo)} · ${DateFormat.Hm().format(a.quando)}'),
                  ),
              ]),
            ),
        ]),
      ),
    ]);
  }

  Widget _cartao(BuildContext context, IconData i, String t, String valor, String sub, {VoidCallback? aoTocar}) => SizedBox(
        width: 200,
        child: Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: aoTocar,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [Icon(i, size: 18, color: Theme.of(context).colorScheme.primary), const SizedBox(width: 6), Text(t)]),
                const SizedBox(height: 8),
                Text(valor, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()])),
                Text(sub, style: TextStyle(color: Cores.fraco(context), fontSize: 12.5)),
              ]),
            ),
          ),
        ),
      );

  Widget _aviso(BuildContext context, String texto, String tipo) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Cores.situacao(context, tipo).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            Icon(tipo == 'erro' ? Icons.error_outline : Icons.cloud_off, color: Cores.situacao(context, tipo)),
            const SizedBox(width: 10),
            Expanded(child: Text(texto)),
          ]),
        ),
      );

  Widget _confirmacao(BuildContext context, dynamic ex) {
    final par = c.pares.where((x) => x['id'] == ex.par).firstOrNull;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Cores.situacao(context, 'alerta').withValues(alpha: 0.13), borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.warning_amber_rounded, color: Cores.situacao(context, 'alerta')),
            const SizedBox(width: 8),
            Expanded(
                child: Text('${ex.total} itens seriam apagados de uma vez em "${par?['nome'] ?? 'uma pasta'}"',
                    style: const TextStyle(fontWeight: FontWeight.w700))),
          ]),
          const SizedBox(height: 6),
          Text('${ex.naNuvem} na nuvem, ${ex.noComputador} neste computador. Se você não apagou isso, pode ser um disco desconectado ou uma pasta movida.'),
          const SizedBox(height: 6),
          for (final e in (ex.exemplos as List<String>).take(5))
            Text('• $e', style: TextStyle(color: Cores.fraco(context), fontSize: 12.5), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 10),
          Wrap(spacing: 10, children: [
            FilledButton(onPressed: () => c.confirmarExclusao(ex.par as int), child: const Text('Apagar mesmo assim')),
            OutlinedButton(onPressed: () => c.manterExclusao(ex.par as int), child: const Text('Agora não')),
          ]),
        ]),
      ),
    );
  }
}

IconData _icone(String t) => switch (t) {
      'enviado' => Icons.cloud_upload_outlined,
      'baixado' => Icons.cloud_download_outlined,
      'conflito' => Icons.call_split,
      'erro' => Icons.error_outline,
      _ => Icons.info_outline,
    };

String _rotulo(String t) => switch (t) {
      'enviado' => 'Enviado',
      'baixado' => 'Baixado',
      'conflito' => 'Conflito: as duas versões foram guardadas',
      'erro' => 'Erro',
      'pausado' => 'Pasta parada',
      _ => t,
    };
