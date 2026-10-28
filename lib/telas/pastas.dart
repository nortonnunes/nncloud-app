import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../servicos/controle.dart';
import '../tema.dart';
import '../widgets/cabecalho.dart';

class TelaPastas extends StatelessWidget {
  final Controle c;
  const TelaPastas(this.c, {super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(28), children: [
      Row(children: [
        Expanded(child: Text('Pastas sincronizadas', style: Theme.of(context).textTheme.headlineSmall)),
        FilledButton.icon(onPressed: () => _adicionar(context), icon: const Icon(Icons.add), label: const Text('Adicionar pasta')),
      ]),
      const SizedBox(height: 6),
      Text('Cada pasta do computador fica igual a uma pasta do NN Cloud, nos dois sentidos.', style: TextStyle(color: Cores.fraco(context))),
      const SizedBox(height: 20),
      if (c.pares.isEmpty)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(children: [
              Icon(Icons.folder_copy_outlined, size: 44, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 10),
              const Text('Nenhuma pasta sincronizada', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('Escolha uma pasta do computador para começar.', style: TextStyle(color: Cores.fraco(context))),
            ]),
          ),
        ),
      for (final pr in c.pares) ...[_cartao(context, pr), const SizedBox(height: 12)],
    ]);
  }

  Widget _cartao(BuildContext context, Map<String, dynamic> pr) {
    final id = pr['id'] as int;
    final pausadoPar = c.arm.pref<List>('pares_pausados', const []).contains(id);
    final r = c.resultados[id];
    final (rot, tipo) = pausadoPar || c.pausado
        ? ('Pausada', 'neutro')
        : r == null
            ? ('Aguardando', 'neutro')
            : switch (r.estado) {
                'ok' => ('Em dia', 'ok'),
                'offline' => ('Offline', 'alerta'),
                'aguardando_confirmacao' => ('Aguardando confirmação', 'alerta'),
                _ => ('Parada', 'erro'),
              };
    final ultimo = pr['ultimo_sync_em'] as String?;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.folder, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(child: Text((pr['nome'] as String?)?.isNotEmpty == true ? pr['nome'] as String : 'Pasta', style: Theme.of(context).textTheme.titleMedium)),
            Selo(rot, Cores.situacao(context, tipo)),
          ]),
          const SizedBox(height: 10),
          _linha(context, Icons.computer, pr['caminho_local'] as String),
          _linha(context, Icons.cloud_outlined, pr['raiz_nome'] as String? ?? 'Meu Drive'),
          _linha(context, Icons.description_outlined,
              '${NumberFormat.decimalPattern('pt_BR').format(pr['arquivos'] ?? 0)} arquivo(s)${ultimo != null ? ' · sincronizada em ${ultimo.substring(8, 10)}/${ultimo.substring(5, 7)} às ${ultimo.substring(11, 16)}' : ''}'),
          if (r?.mensagem != null && r!.estado != 'ok') ...[
            const SizedBox(height: 8),
            Text(r.mensagem!, style: TextStyle(color: Cores.situacao(context, 'erro'))),
          ],
          const SizedBox(height: 12),
          Wrap(spacing: 8, children: [
            OutlinedButton.icon(onPressed: () => c.abrirPasta(pr['caminho_local'] as String), icon: const Icon(Icons.folder_open), label: const Text('Abrir pasta')),
            OutlinedButton.icon(
              onPressed: () => c.pausarPar(id, !pausadoPar),
              icon: Icon(pausadoPar ? Icons.play_arrow : Icons.pause),
              label: Text(pausadoPar ? 'Retomar' : 'Pausar'),
            ),
            TextButton.icon(
              onPressed: () => _remover(context, pr),
              icon: Icon(Icons.link_off, color: Cores.situacao(context, 'erro')),
              label: Text('Parar de sincronizar', style: TextStyle(color: Cores.situacao(context, 'erro'))),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _linha(BuildContext context, IconData i, String t) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(children: [
          Icon(i, size: 15, color: Cores.fraco(context)),
          const SizedBox(width: 8),
          Expanded(child: Text(t, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Cores.fraco(context)))),
        ]),
      );

  Future<void> _remover(BuildContext context, Map<String, dynamic> pr) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Parar de sincronizar?'),
        content: Text('A pasta "${pr['caminho_local']}" e os arquivos dela continuam no computador, e o que está no NN Cloud continua lá. '
            'Só deixam de ser mantidos iguais.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Parar de sincronizar')),
        ],
      ),
    );
    if (ok != true) return;
    final erro = await c.removerPar(pr['id'] as int);
    if (erro != null && context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(erro)));
  }

  Future<void> _adicionar(BuildContext context) async {
    final pasta = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Escolha a pasta do computador');
    if (pasta == null || !context.mounted) return;
    await showDialog<void>(context: context, builder: (_) => _DialogoDestino(c, pasta));
  }
}

/// Escolhe para onde a pasta vai na nuvem: o Meu Drive (numa pasta com o mesmo
/// nome), uma pasta existente ou um Drive compartilhado.
class _DialogoDestino extends StatefulWidget {
  final Controle c;
  final String pasta;
  const _DialogoDestino(this.c, this.pasta);
  @override
  State<_DialogoDestino> createState() => _DialogoDestinoState();
}

class _DialogoDestinoState extends State<_DialogoDestino> {
  bool mesmoNome = true;
  List<Map<String, dynamic>> espacos = [];
  Map<String, dynamic>? espaco;
  final List<Map<String, dynamic>> trilha = [];   // pastas abertas
  List<Map<String, dynamic>> pastas = [];
  bool carregando = false, salvando = false;
  String? erro;

  @override
  void initState() {
    super.initState();
    _carregarEspacos();
  }

  Future<void> _carregarEspacos() async {
    setState(() => carregando = true);
    try {
      espacos = await widget.c.api!.espacos();
    } catch (e) {
      erro = '$e';
    }
    setState(() => carregando = false);
  }

  Future<void> _abrir(Map<String, dynamic>? esp, Map<String, dynamic>? pasta) async {
    setState(() => carregando = true);
    try {
      if (esp != null) {
        espaco = esp;
        trilha.clear();
      }
      if (pasta != null) trilha.add(pasta);
      final r = await widget.c.api!.pastas(espacoId: trilha.isEmpty ? espaco!['id'] as int : null, pastaId: trilha.isEmpty ? null : trilha.last['id'] as int);
      pastas = (r['pastas'] as List).cast<Map<String, dynamic>>();
    } catch (e) {
      erro = '$e';
    }
    setState(() => carregando = false);
  }

  Future<void> _salvar() async {
    setState(() {
      salvando = true;
      erro = null;
    });
    final e = mesmoNome
        ? await widget.c.adicionarPar(widget.pasta, mesmoNome: true)
        : await widget.c.adicionarPar(widget.pasta, espacoId: espaco?['id'] as int?, pastaId: trilha.isEmpty ? null : trilha.last['id'] as int);
    if (!mounted) return;
    if (e == null) {
      Navigator.pop(context);
    } else {
      setState(() {
        salvando = false;
        erro = e;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final nome = widget.pasta.split(RegExp(r'[\\/]')).where((s) => s.isNotEmpty).last;
    final podeSalvar = !salvando && (mesmoNome || (espaco != null && (trilha.isEmpty ? espaco!['pode_editar'] == true : trilha.last['pode_editar'] == true)));
    return AlertDialog(
      title: const Text('Para onde vai esta pasta?'),
      content: SizedBox(
        width: 520,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.pasta, style: TextStyle(color: Cores.fraco(context)), maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 12),
          RadioGroup<bool>(
            groupValue: mesmoNome,
            onChanged: (v) {
              setState(() => mesmoNome = v ?? true);
              if (v == false && espaco == null && espacos.isNotEmpty) _abrir(espacos.first, null);
            },
            child: Column(children: [
              RadioListTile<bool>(
                value: true,
                title: Text('Meu Drive, numa pasta chamada "$nome"'),
                subtitle: const Text('Recomendado. Se a pasta já existir lá, ela é usada.'),
              ),
              const RadioListTile<bool>(
                value: false,
                title: Text('Escolher uma pasta do NN Cloud'),
                subtitle: Text('Inclusive de um Drive compartilhado.'),
              ),
            ]),
          ),
          if (!mesmoNome) ...[
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              key: ValueKey(espaco?['id']),
              initialValue: espaco?['id'] as int?,
              decoration: const InputDecoration(labelText: 'Espaço'),
              items: [for (final e in espacos) DropdownMenuItem(value: e['id'] as int, child: Text(e['nome'] as String))],
              onChanged: (id) => _abrir(espacos.firstWhere((e) => e['id'] == id), null),
            ),
            const SizedBox(height: 8),
            Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
              TextButton(onPressed: espaco == null ? null : () => _abrir(espaco, null), child: Text(espaco?['nome'] as String? ?? '')),
              for (var i = 0; i < trilha.length; i++) ...[
                const Icon(Icons.chevron_right, size: 16),
                TextButton(
                  onPressed: () {
                    final alvo = trilha[i];
                    trilha.removeRange(i, trilha.length);
                    _abrir(null, alvo);
                  },
                  child: Text(trilha[i]['nome'] as String),
                ),
              ],
            ]),
            Container(
              height: 200,
              decoration: BoxDecoration(border: Border.all(color: Theme.of(context).colorScheme.outlineVariant), borderRadius: BorderRadius.circular(10)),
              child: carregando
                  ? const Center(child: CircularProgressIndicator())
                  : pastas.isEmpty
                      ? Center(child: Text('Nenhuma subpasta. A sincronização usa esta.', style: TextStyle(color: Cores.fraco(context))))
                      : ListView(children: [
                          for (final pz in pastas)
                            ListTile(dense: true, leading: const Icon(Icons.folder_outlined), title: Text(pz['nome'] as String), onTap: () => _abrir(null, pz)),
                        ]),
            ),
            const SizedBox(height: 6),
            Text('A sincronização vai usar: ${trilha.isEmpty ? (espaco?['nome'] ?? '') : trilha.last['nome']}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
          if (erro != null) ...[const SizedBox(height: 10), Text(erro!, style: TextStyle(color: Cores.situacao(context, 'erro')))],
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: podeSalvar ? _salvar : null, child: Text(salvando ? 'Adicionando…' : 'Sincronizar')),
      ],
    );
  }
}
