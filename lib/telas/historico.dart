import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../servicos/controle.dart';
import '../tema.dart';

/// O histórico deste computador (guardado no NN Conecta, 90 dias).
class TelaHistorico extends StatefulWidget {
  final Controle c;
  const TelaHistorico(this.c, {super.key});
  @override
  State<TelaHistorico> createState() => _TelaHistoricoState();
}

const _acoes = {
  '': 'Tudo',
  'enviado': 'Enviados',
  'baixado': 'Baixados',
  'atualizado': 'Atualizados',
  'renomeado': 'Renomeados',
  'movido': 'Movidos',
  'excluido_local': 'Apagados no computador',
  'excluido_nuvem': 'Apagados na nuvem',
  'conflito': 'Conflitos',
  'liberado': 'Liberados (só na nuvem)',
  'erro': 'Erros',
};

class _TelaHistoricoState extends State<TelaHistorico> {
  String acao = '';
  final busca = TextEditingController();
  List<Map<String, dynamic>> linhas = [];
  bool carregando = false;
  String? erro;
  Timer? _espera;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    busca.dispose();
    _espera?.cancel();
    super.dispose();
  }

  Future<void> _carregar() async {
    if (widget.c.api == null) return;
    setState(() => carregando = true);
    try {
      final r = await widget.c.api!.pedir('GET', 'historico', query: {'acao': acao, 'busca': busca.text.trim(), 'limite': '200'}) as Map;
      linhas = (r['linhas'] as List).cast<Map<String, dynamic>>();
      erro = null;
    } catch (e) {
      erro = 'Não foi possível carregar o histórico agora.';
    }
    if (mounted) setState(() => carregando = false);
  }

  String? _local(Map<String, dynamic> l) {
    final par = int.tryParse('${l['sincronizacao_id']}');
    final pr = widget.c.pares.where((x) => x['id'] == par).firstOrNull;
    if (pr == null) return null;
    return p.joinAll([pr['caminho_local'] as String, ...(l['caminho'] as String).split('/')]);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Histórico', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 14),
        Row(children: [
          SizedBox(
            width: 230,
            child: DropdownButtonFormField<String>(
              initialValue: acao,
              decoration: const InputDecoration(labelText: 'Mostrar'),
              items: [for (final e in _acoes.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (v) {
                acao = v ?? '';
                _carregar();
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: busca,
              decoration: const InputDecoration(labelText: 'Buscar pelo nome', prefixIcon: Icon(Icons.search)),
              onChanged: (_) {
                _espera?.cancel();
                _espera = Timer(const Duration(milliseconds: 400), _carregar);
              },
            ),
          ),
          IconButton(onPressed: _carregar, icon: const Icon(Icons.refresh), tooltip: 'Atualizar'),
        ]),
        const SizedBox(height: 14),
        if (carregando) const LinearProgressIndicator(),
        if (erro != null) Text(erro!, style: TextStyle(color: Cores.situacao(context, 'erro'))),
        Expanded(
          child: linhas.isEmpty && !carregando
              ? Center(child: Text('Nada encontrado.', style: TextStyle(color: Cores.fraco(context))))
              : Card(
                  child: ListView.separated(
                    itemCount: linhas.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final l = linhas[i];
                      final local = _local(l);
                      return ListTile(
                        leading: Icon(_icone(l['acao'] as String),
                            color: Cores.situacao(context, l['acao'] == 'erro' ? 'erro' : (l['acao'] == 'conflito' ? 'alerta' : 'neutro'))),
                        title: Text(l['caminho'] as String? ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text([
                          _acoes[l['acao']] ?? l['acao'],
                          _quando('${l['ocorrido_em'] ?? ''}'),
                          if ((l['detalhe'] as String?)?.isNotEmpty == true) l['detalhe'],
                        ].join(' · ')),
                        trailing: local == null
                            ? null
                            : IconButton(
                                tooltip: switch (Theme.of(context).platform) {
                                  TargetPlatform.macOS => 'Mostrar no Finder',
                                  TargetPlatform.linux => 'Mostrar na pasta',
                                  _ => 'Mostrar no Explorer',
                                },
                                icon: const Icon(Icons.folder_open_outlined),
                                onPressed: () => widget.c.mostrarNoGerenciador(local),
                              ),
                      );
                    },
                  ),
                ),
        ),
      ]),
    );
  }
}

/// "2026-10-28 13:50:14" → "28/10 13:50".
String _quando(String s) => s.length < 16 ? s : '${s.substring(8, 10)}/${s.substring(5, 7)} ${s.substring(11, 16)}';

IconData _icone(String a) => switch (a) {
      'enviado' || 'atualizado' => Icons.cloud_upload_outlined,
      'baixado' => Icons.cloud_download_outlined,
      'renomeado' || 'movido' => Icons.drive_file_move_outline,
      'excluido_local' || 'excluido_nuvem' => Icons.delete_outline,
      'conflito' => Icons.call_split,
      'liberado' => Icons.cloud_done_outlined,
      'erro' => Icons.error_outline,
      _ => Icons.history,
    };
