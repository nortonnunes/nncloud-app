import 'dart:io';

import 'package:flutter/material.dart';

import '../config.dart';
import '../servicos/controle.dart';
import '../servicos/sistema.dart';
import '../tema.dart';

class TelaConfiguracoes extends StatefulWidget {
  final Controle c;
  final ValueNotifier<ThemeMode> tema;
  const TelaConfiguracoes(this.c, this.tema, {super.key});
  @override
  State<TelaConfiguracoes> createState() => _TelaConfiguracoesState();
}

class _TelaConfiguracoesState extends State<TelaConfiguracoes> {
  bool? inicio;
  late final TextEditingController ignorados, proxy, api;

  Controle get c => widget.c;

  @override
  void initState() {
    super.initState();
    ignorados = TextEditingController(text: (c.arm.pref<List>('ignorados_extra', const [])).join('\n'));
    proxy = TextEditingController(text: c.arm.pref<String>('proxy', ''));
    api = TextEditingController(text: c.baseApi);
    InicioComSistema.ativo().then((v) => mounted ? setState(() => inicio = v) : null);
  }

  @override
  void dispose() {
    ignorados.dispose();
    proxy.dispose();
    api.dispose();
    super.dispose();
  }

  void _aviso(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  @override
  Widget build(BuildContext context) {
    final pessoa = (c.eu?['pessoa'] as Map?) ?? {};
    final so = Platform.isWindows ? 'windows' : (Platform.isLinux ? 'linux' : 'macos');
    final nova = c.eu?['app']?[so] as Map?;
    return ListView(padding: const EdgeInsets.all(28), children: [
      Text('Configurações', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 18),
      _secao('Conta', [
        ListTile(
          leading: const Icon(Icons.account_circle_outlined),
          title: Text('${pessoa['nome'] ?? ''}'),
          subtitle: Text('${pessoa['email'] ?? ''} · este computador: ${c.nomeComputador}'),
          trailing: OutlinedButton(onPressed: _desconectar, child: const Text('Desconectar')),
        ),
      ]),
      _secao('Geral', [
        SwitchListTile(
          title: Text('Iniciar com o ${Platform.isWindows ? 'Windows' : (Platform.isLinux ? 'sistema' : 'macOS')}'),
          subtitle: const Text('Abre escondido, na barra de menus / bandeja, e começa a sincronizar.'),
          value: inicio ?? false,
          onChanged: inicio == null
              ? null
              : (v) async {
                  final erro = await InicioComSistema.definir(v);
                  if (erro != null) _aviso(erro);
                  final a = await InicioComSistema.ativo();
                  if (mounted) setState(() => inicio = a);
                },
        ),
        SwitchListTile(
          title: const Text('Notificações'),
          subtitle: const Text('Avisos de conclusão, conflitos, pastas paradas e novas versões.'),
          value: c.notificar,
          onChanged: (v) => setState(() => c.arm.definir('notificacoes', v)),
        ),
        ListTile(
          title: const Text('Aparência'),
          trailing: SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(value: ThemeMode.system, label: Text('Sistema')),
              ButtonSegment(value: ThemeMode.light, label: Text('Claro')),
              ButtonSegment(value: ThemeMode.dark, label: Text('Escuro')),
            ],
            selected: {widget.tema.value},
            onSelectionChanged: (s) {
              widget.tema.value = s.first;
              c.arm.definir('tema', s.first.name);
              setState(() {});
            },
          ),
        ),
      ]),
      _secao('Arquivos ignorados', [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Além do lixo do sistema (.DS_Store, Thumbs.db, temporários do Office…), ignorar também (um por linha; aceita * no começo ou no fim):',
                style: TextStyle(color: Cores.fraco(context))),
            const SizedBox(height: 8),
            TextField(controller: ignorados, maxLines: 4, decoration: const InputDecoration(hintText: 'node_modules\n.git\n*.bak')),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: () {
                c.arm.definir('ignorados_extra', ignorados.text.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList());
                _aviso('Salvo. Vale a partir do próximo ciclo.');
                c.iniciar();
              },
              child: const Text('Salvar'),
            ),
          ]),
        ),
      ]),
      _secao('Rede', [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(controller: proxy, decoration: const InputDecoration(labelText: 'Proxy (host:porta) — em branco, conexão direta')),
            const SizedBox(height: 10),
            TextField(controller: api, decoration: const InputDecoration(labelText: 'Endereço da API do NN Conecta')),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: () {
                c.arm.definir('proxy', proxy.text.trim());
                c.arm.definir('api', api.text.trim().isEmpty ? AppConfig.apiPadrao : api.text.trim().replaceAll(RegExp(r'/+$'), ''));
                _aviso('Salvo.');
                c.iniciar();
              },
              child: const Text('Salvar'),
            ),
          ]),
        ),
      ]),
      _secao('Sobre', [
        ListTile(
          leading: Image.asset('assets/icon.png', width: 32, height: 32),
          title: const Text('NN Cloud ${AppConfig.versao}'),
          subtitle: Text(nova != null && nova['versao'] != AppConfig.versao ? 'Versão ${nova['versao']} disponível.' : 'Você está na versão mais recente.'),
          trailing: Wrap(spacing: 8, children: [
            if (nova != null && nova['versao'] != AppConfig.versao)
              FilledButton(
                onPressed: () => c.abrirNavegador('${c.eu?['config']?['web'] ?? ''}/aplicativo?so=$so'),
                child: const Text('Baixar'),
              ),
            OutlinedButton(onPressed: () => c.abrirNavegador('${c.eu?['config']?['web'] ?? ''}'), child: const Text('Abrir no navegador')),
          ]),
        ),
      ]),
    ]);
  }

  Widget _secao(String t, List<Widget> filhos) => Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(left: 4, bottom: 6), child: Text(t, style: Theme.of(context).textTheme.titleMedium)),
          Card(child: Column(children: filhos)),
        ]),
      );

  Future<void> _desconectar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Desconectar este computador?'),
        content: const Text('A sincronização para. Os arquivos continuam no computador e no NN Cloud.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Desconectar')),
        ],
      ),
    );
    if (ok == true) await c.desconectar();
  }
}
