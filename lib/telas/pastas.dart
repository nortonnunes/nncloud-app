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
      Text('Cada pasta do computador fica igual a uma pasta do NN Cloud, nos dois sentidos — ou funciona como pasta de envio, '
          'que manda tudo para a nuvem e libera o espaço. Em Opções dá para deixar subpastas só na nuvem.',
          style: TextStyle(color: Cores.fraco(context))),
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
    final envio = pr['modo'] == 'envio';
    final seletivas = ((pr['so_nuvem'] as List?) ?? const []).length;
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
              '${NumberFormat.decimalPattern('pt_BR').format(pr['arquivos'] ?? 0)} arquivo(s) neste computador${ultimo != null ? ' · sincronizada em ${ultimo.substring(8, 10)}/${ultimo.substring(5, 7)} às ${ultimo.substring(11, 16)}' : ''}'),
          if (envio)
            _linha(context, Icons.outbox_outlined, 'Pasta de envio: o que entra sobe para a nuvem e sai deste computador')
          else if (seletivas > 0)
            _linha(context, Icons.cloud_queue, '$seletivas subpasta(s) só na nuvem'),
          if ((r?.soNaNuvem ?? 0) > 0)
            _linha(context, Icons.cloud_done_outlined,
                '${NumberFormat.decimalPattern('pt_BR').format(r!.soNaNuvem)} arquivo(s) só na nuvem (${bytesTexto(r.bytesSoNaNuvem)}) — não ocupam espaço aqui'),
          if ((r?.aguardandoLiberar ?? 0) > 0)
            _linha(context, Icons.hourglass_bottom, '${r!.aguardandoLiberar} arquivo(s) alterado(s) há pouco: saem do computador em alguns minutos'),
          if (r?.mensagem != null && r!.estado != 'ok') ...[
            const SizedBox(height: 8),
            Text(r.mensagem!, style: TextStyle(color: Cores.situacao(context, 'erro'))),
          ],
          const SizedBox(height: 12),
          Wrap(spacing: 8, children: [
            OutlinedButton.icon(onPressed: () => c.abrirPasta(pr['caminho_local'] as String), icon: const Icon(Icons.folder_open), label: const Text('Abrir pasta')),
            OutlinedButton.icon(
              onPressed: () => showDialog<void>(context: context, builder: (_) => DialogoOpcoes(c, pr)),
              icon: const Icon(Icons.tune),
              label: const Text('Opções'),
            ),
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
  bool envio = false;
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
        ? await widget.c.adicionarPar(widget.pasta, mesmoNome: true, envio: envio)
        : await widget.c.adicionarPar(widget.pasta,
            espacoId: espaco?['id'] as int?, pastaId: trilha.isEmpty ? null : trilha.last['id'] as int, envio: envio);
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
          const Divider(height: 24),
          SwitchListTile(
            value: envio,
            onChanged: (v) => setState(() => envio = v),
            contentPadding: EdgeInsets.zero,
            title: const Text('Pasta de envio (libera espaço)'),
            subtitle: const Text('O que entra na pasta sobe para a nuvem e sai deste computador depois de confirmado. '
                'Nada desce da nuvem. Ideal para scanner, backup e arquivo morto.'),
          ),
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

/// Opções de uma pasta sincronizada: espelho ou pasta de envio, e as subpastas
/// que ficam SÓ NA NUVEM neste computador (sincronização seletiva).
///
/// Marcado = fica no computador. Desmarcar uma pasta tira do computador ela e
/// tudo dentro (as subpastas aparecem desabilitadas). Antes de salvar, a tela
/// diz o que vai acontecer — principalmente quanto vai DESCER.
class DialogoOpcoes extends StatefulWidget {
  final Controle c;
  final Map<String, dynamic> par;
  const DialogoOpcoes(this.c, this.par, {super.key});
  @override
  State<DialogoOpcoes> createState() => _DialogoOpcoesState();
}

class _No {
  final int id;
  final String nome;
  final int nivel;
  List<_No>? filhos;   // null = ainda não carregado
  bool aberto = false, carregando = false;
  _No(this.id, this.nome, this.nivel);
}

class _DialogoOpcoesState extends State<DialogoOpcoes> {
  late bool envio;
  late Set<int> soNuvem;
  late final bool envioAntes;
  late final Set<int> soNuvemAntes;
  List<_No>? raiz;
  bool salvando = false;
  String? erro;

  int get par => widget.par['id'] as int;

  @override
  void initState() {
    super.initState();
    envio = envioAntes = widget.par['modo'] == 'envio';
    soNuvemAntes = {for (final x in (widget.par['so_nuvem'] as List?) ?? const []) if (x is int) x};
    soNuvem = {...soNuvemAntes};
    _carregar(null);
  }

  Future<List<_No>> _pastas(int? pastaId, int nivel) async {
    final r = pastaId == null
        ? (widget.par['raiz_id'] == null
            ? await widget.c.api!.pastas(espacoId: widget.par['espaco_id'] as int)
            : await widget.c.api!.pastas(pastaId: widget.par['raiz_id'] as int))
        : await widget.c.api!.pastas(pastaId: pastaId);
    return [for (final x in (r['pastas'] as List).cast<Map<String, dynamic>>()) _No(x['id'] as int, x['nome'] as String, nivel)];
  }

  Future<void> _carregar(_No? no) async {
    try {
      if (no == null) {
        final l = await _pastas(null, 0);
        if (mounted) setState(() => raiz = l);
      } else {
        setState(() => no.carregando = true);
        no.filhos = await _pastas(no.id, no.nivel + 1);
        if (mounted) setState(() => no.carregando = false);
      }
    } catch (e) {
      if (mounted) setState(() => erro = '$e');
    }
  }

  List<Widget> _arvore(List<_No> nos, bool paiFora) => [
        for (final n in nos) ...[
          Padding(
            padding: EdgeInsets.only(left: n.nivel * 22.0),
            child: Row(children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(n.aberto ? Icons.expand_more : Icons.chevron_right, size: 20),
                tooltip: n.aberto ? 'Fechar' : 'Ver subpastas',
                onPressed: () {
                  setState(() => n.aberto = !n.aberto);
                  if (n.aberto && n.filhos == null) _carregar(n);
                },
              ),
              Checkbox(
                value: !paiFora && !soNuvem.contains(n.id),
                onChanged: paiFora
                    ? null
                    : (v) => setState(() => v == true ? soNuvem.remove(n.id) : soNuvem.add(n.id)),
              ),
              Icon(Icons.folder_outlined, size: 18, color: Cores.fraco(context)),
              const SizedBox(width: 6),
              Expanded(child: Text(n.nome, overflow: TextOverflow.ellipsis)),
              if (paiFora || soNuvem.contains(n.id))
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Text('só na nuvem', style: TextStyle(color: Cores.fraco(context), fontSize: 12)),
                ),
            ]),
          ),
          if (n.aberto && n.carregando)
            Padding(padding: EdgeInsets.only(left: n.nivel * 22.0 + 52, bottom: 6), child: const LinearProgressIndicator()),
          if (n.aberto && n.filhos != null) ..._arvore(n.filhos!, paiFora || soNuvem.contains(n.id)),
        ],
      ];

  /// O que vai acontecer ao salvar, em frases.
  List<String> _efeitos() {
    final out = <String>[];
    if (envio && !envioAntes) {
      out.add('Tudo o que já está igual na nuvem sai deste computador e fica só na nuvem (acessível pelo NN Cloud no navegador). '
          'Arquivos alterados nos últimos 5 minutos esperam um pouco.');
      return out;
    }
    if (!envio && envioAntes) {
      final t = widget.c.tamanhoNaNuvem(par);
      out.add('Vai baixar de volta o que está só na nuvem: até ${t.arquivos} arquivo(s), ${bytesTexto(t.bytes)}. Confira se há espaço no disco.');
      return out;
    }
    if (envio) return out;
    final voltam = soNuvemAntes.difference(soNuvem);
    if (voltam.isNotEmpty) {
      var n = 0, b = 0;
      for (final id in voltam) {
        final t = widget.c.tamanhoNaNuvem(par, pastaId: id);
        n += t.arquivos;
        b += t.bytes;
      }
      out.add('${voltam.length} pasta(s) voltam para o computador: vão descer $n arquivo(s), ${bytesTexto(b)}.');
    }
    final saem = soNuvem.difference(soNuvemAntes);
    if (saem.isNotEmpty) {
      out.add('${saem.length} pasta(s) saem do computador e ficam só na nuvem. Só sai o que já está igual na nuvem; '
          'o que foi alterado aqui sobe antes.');
    }
    return out;
  }

  Future<void> _salvar() async {
    setState(() {
      salvando = true;
      erro = null;
    });
    final e = await widget.c.salvarOpcoesPar(par, envio: envio, soNuvem: envio ? soNuvemAntes : soNuvem);
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
    final efeitos = _efeitos();
    final mudou = envio != envioAntes || (!envio && (soNuvem.length != soNuvemAntes.length || !soNuvem.containsAll(soNuvemAntes)));
    return AlertDialog(
      title: Text('Opções de "${(widget.par['nome'] as String?)?.isNotEmpty == true ? widget.par['nome'] : 'Pasta'}"'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            RadioGroup<bool>(
              groupValue: envio,
              onChanged: (v) => setState(() => envio = v ?? false),
              child: const Column(children: [
                RadioListTile<bool>(
                  value: false,
                  title: Text('Espelho'),
                  subtitle: Text('O computador e a nuvem ficam iguais, nos dois sentidos.'),
                ),
                RadioListTile<bool>(
                  value: true,
                  title: Text('Pasta de envio (libera espaço)'),
                  subtitle: Text('O que entra na pasta sobe para a nuvem e sai deste computador. Nada desce da nuvem.'),
                ),
              ]),
            ),
            if (!envio) ...[
              const Divider(height: 24),
              Text('Pastas neste computador', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              Text('Desmarque o que pode ficar só na nuvem. Os arquivos continuam no NN Cloud e voltam ao marcar de novo.',
                  style: TextStyle(color: Cores.fraco(context))),
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxHeight: 260, minHeight: 80),
                decoration: BoxDecoration(border: Border.all(color: Theme.of(context).colorScheme.outlineVariant), borderRadius: BorderRadius.circular(10)),
                child: raiz == null
                    ? const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
                    : raiz!.isEmpty
                        ? Center(child: Padding(padding: const EdgeInsets.all(20), child: Text('Esta pasta não tem subpastas na nuvem.', style: TextStyle(color: Cores.fraco(context)))))
                        : ListView(shrinkWrap: true, padding: const EdgeInsets.symmetric(vertical: 4), children: _arvore(raiz!, false)),
              ),
            ],
            if (mudou && efeitos.isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (final f in efeitos)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Icon(Icons.info_outline, size: 16),
                        const SizedBox(width: 8),
                        Expanded(child: Text(f)),
                      ]),
                    ),
                ]),
              ),
            ],
            if (erro != null) ...[const SizedBox(height: 10), Text(erro!, style: TextStyle(color: Cores.situacao(context, 'erro')))],
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: !mudou || salvando ? null : _salvar, child: Text(salvando ? 'Salvando…' : 'Salvar')),
      ],
    );
  }
}
