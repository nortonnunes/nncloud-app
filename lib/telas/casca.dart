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
        // O número da aba é FIXO (0 Visão geral, 1 Pastas, 2 Histórico, 3 Problemas,
        // 4 Configurações): a notificação, a bandeja e a Visão geral pulam para ele.
        // A aba Pastas só existe onde se usa pasta sincronizada (ver Controle.mostraPastas);
        // sem ela, o número 1 abre a Visão geral.
        final abas = <(int, NavigationRailDestination, Widget Function())>[
          (0, const NavigationRailDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: Text('Visão geral')),
              () => TelaVisaoGeral(c, (i) => widget.aba.value = i)),
          if (c.mostraPastas)
            (1, const NavigationRailDestination(icon: Icon(Icons.folder_outlined), selectedIcon: Icon(Icons.folder), label: Text('Pastas')),
                () => TelaPastas(c)),
          (2, const NavigationRailDestination(icon: Icon(Icons.history), label: Text('Histórico')), () => TelaHistorico(c)),
          (
            3,
            NavigationRailDestination(
              icon: Badge(isLabelVisible: nProblemas > 0, label: Text('$nProblemas'), child: const Icon(Icons.report_outlined)),
              label: const Text('Problemas'),
            ),
            () => TelaProblemas(c)
          ),
          (4, const NavigationRailDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: Text('Configurações')),
              () => TelaConfiguracoes(c, widget.tema)),
        ];
        final atual = abas.indexWhere((a) => a.$1 == aba).clamp(0, abas.length - 1);
        return Scaffold(
          body: Row(children: [
            NavigationRail(
              selectedIndex: atual,
              onDestinationSelected: (i) => widget.aba.value = abas[i].$1,
              labelType: NavigationRailLabelType.all,
              backgroundColor: cs.surfaceContainerLow,
              leading: Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 18),
                child: Image.asset('assets/icon.png', width: 40, height: 40),
              ),
              destinations: [for (final a in abas) a.$2],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: abas[atual].$3()),
          ]),
        );
      },
    );
  }
}
