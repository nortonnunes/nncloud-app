import 'package:flutter/material.dart';

import '../servicos/controle.dart';
import 'configuracoes.dart';
import 'historico.dart';
import 'pastas.dart';
import 'problemas.dart';
import 'visao_geral.dart';

/// A janela principal: navegação à esquerda e a tela escolhida.
class Casca extends StatefulWidget {
  final Controle c;
  final ValueNotifier<ThemeMode> tema;
  final ValueNotifier<int> aba;
  const Casca(this.c, this.tema, this.aba, {super.key});
  @override
  State<Casca> createState() => _CascaState();
}

class _CascaState extends State<Casca> {
  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final cs = Theme.of(context).colorScheme;
    final nProblemas = c.problemas.length + c.resultados.values.where((r) => r.estado == 'erro').length + c.aguardando.length;
    return ValueListenableBuilder<int>(
      valueListenable: widget.aba,
      builder: (context, aba, _) {
        final telas = [
          TelaVisaoGeral(c, (i) => widget.aba.value = i),
          TelaPastas(c),
          TelaHistorico(c),
          TelaProblemas(c),
          TelaConfiguracoes(c, widget.tema),
        ];
        return Scaffold(
          body: Row(children: [
            NavigationRail(
              selectedIndex: aba,
              onDestinationSelected: (i) => widget.aba.value = i,
              labelType: NavigationRailLabelType.all,
              backgroundColor: cs.surfaceContainerLow,
              leading: Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 18),
                child: Image.asset('assets/icon.png', width: 40, height: 40),
              ),
              destinations: [
                const NavigationRailDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: Text('Visão geral')),
                const NavigationRailDestination(icon: Icon(Icons.folder_outlined), selectedIcon: Icon(Icons.folder), label: Text('Pastas')),
                const NavigationRailDestination(icon: Icon(Icons.history), label: Text('Histórico')),
                NavigationRailDestination(
                  icon: Badge(isLabelVisible: nProblemas > 0, label: Text('$nProblemas'), child: const Icon(Icons.report_outlined)),
                  label: const Text('Problemas'),
                ),
                const NavigationRailDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: Text('Configurações')),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: telas[aba]),
          ]),
        );
      },
    );
  }
}
