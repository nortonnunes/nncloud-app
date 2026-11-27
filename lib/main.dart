// NN Conversas — as Conversas do NN Conecta no computador (Windows, macOS e Linux).
//
// Janela NORMAL, que lembra o tamanho e a posição, aberta nas Conversas. Minimizar
// ou fechar leva para o ícone ao lado do relógio; "Sair" só pelo menu desse ícone.
// Com `--oculto` (início com o sistema) começa já na bandeja — e um comunicado
// traz a janela de volta.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'config.dart';
import 'servicos/armazenamento.dart';
import 'servicos/atualizacao.dart';
import 'servicos/controle.dart';
import 'servicos/janela.dart';
import 'servicos/notificacoes.dart';
import 'servicos/sistema.dart';
import 'servicos/som.dart';
import 'tema.dart';
import 'telas/acesso.dart';
import 'telas/casca.dart';

final navegador = GlobalKey<NavigatorState>();

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('pt_BR');
  final arm = Armazenamento();
  await arm.iniciar();

  Janela.arm = arm;
  final unico = await InstanciaUnica.garantir(arm.dados, () => Janela.mostrar());
  if (!unico) exit(0);   // a outra cópia foi avisada e voltou para a tela

  await windowManager.ensureInitialized();
  final oculto = args.contains('--oculto');
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      size: Janela.tamanhoPadrao,
      minimumSize: Janela.tamanhoMinimo,
      center: true,
      title: AppConfig.nome,
      titleBarStyle: TitleBarStyle.normal,
    ),
    () async {
      await Janela.restaurar();
      if (oculto) {
        await windowManager.setSkipTaskbar(true);
        Janela.naBandeja = true;
      } else {
        await Janela.mostrar();
      }
    },
  );
  await windowManager.setPreventClose(true);

  final notif = Notificacoes();
  final c = Controle(arm)..janelaVisivel = !oculto;
  c.alertas.janelaEmFoco = !oculto;
  // ⚠️ Sem `await`: na primeira abertura o macOS pergunta se o app pode mandar
  // notificações, e o plugin só responde DEPOIS que a pessoa clica. Esperando, a
  // janela ficaria em branco até a resposta. Antes de pronto, `mostrar` só não mostra.
  unawaited(notif.iniciar(aoTocar: (payload) async {
    await Janela.mostrar();
    c.janelaVisivel = true;
    if (payload != null && payload.startsWith('conversa:')) {
      Casca.abrirConversa(int.tryParse(payload.substring(9)) ?? 0);
    }
  }));
  // Mensagem nova: o `Alertas` decide (quadro no canto, notificação, som).
  c.alertas.tocarSom = Som.mensagem;
  c.alertas.mostrarNotificacao = (a) => notif.mostrar(a.tituloNotificacao, a.textoNotificacao, payload: 'conversa:${a.conversa}');

  c.aoChegarComunicado = (novos) async {
    await Janela.chamarAtencao();
    c.janelaVisivel = true;
    unawaited(Som.comunicado());
    final t = novos.length == 1 ? (novos.first['titulo'] ?? 'Comunicado').toString() : '${novos.length} comunicados novos';
    await notif.mostrar('Comunicado', t, payload: 'comunicado');
  };

  final atualizador = Atualizador(c, arm, notif);
  runApp(AppConversas(c, atualizador));
  try {
    await Bandeja(c).iniciar();
  } catch (e) {
    debugPrint('Bandeja indisponível: $e');
  }
  // A janela pode abrir sem foco (outro programa na frente): aí mensagem nova
  // vira notificação, e a conversa aberta não marca como lida.
  if (!oculto) {
    try {
      c.alertas.janelaEmFoco = await windowManager.isFocused();
    } catch (_) {}
  }
  await c.iniciar();
  atualizador.iniciar();
}

class AppConversas extends StatefulWidget {
  final Controle c;
  final Atualizador atualizador;
  const AppConversas(this.c, this.atualizador, {super.key});
  @override
  State<AppConversas> createState() => _AppConversasState();
}

class _AppConversasState extends State<AppConversas> with WindowListener, WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    WidgetsBinding.instance.addObserver(this);
    widget.c.aoMudarVisual = () {
      if (mounted) setState(() {});
    };
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _bandeja() async {
    widget.c.janelaVisivel = false;
    widget.c.alertas.janelaEmFoco = false;
    await Janela.paraBandeja();
    // Versão nova já baixada e conferida: a hora de trocar é quando ninguém está olhando.
    await widget.atualizador.talvezInstalar();
  }

  @override
  void onWindowClose() => _bandeja();

  @override
  void onWindowMinimize() => _bandeja();

  // Tamanho e posição: guardados para a próxima abertura.
  @override
  void onWindowResized() => Janela.mudou();

  @override
  void onWindowMoved() => Janela.mudou();

  @override
  void onWindowMaximize() => Janela.mudou();

  @override
  void onWindowUnmaximize() => Janela.mudou();

  @override
  void onWindowFocus() {
    final voltou = !widget.c.janelaVisivel;
    widget.c.janelaVisivel = true;
    widget.c.alertas.janelaEmFoco = true;
    if (voltou) widget.c.acordou();
  }

  // Atrás de outra janela: a pessoa não está olhando (mensagem nova vira
  // notificação, e a conversa aberta deixa de marcar como lida).
  @override
  void onWindowBlur() => widget.c.alertas.janelaEmFoco = false;

  // O mesmo pelo estado do app (no Linux o gerenciador de janelas não avisa o
  // foco; o Flutter avisa nos três sistemas).
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) {
      if (widget.c.janelaVisivel && !Janela.naBandeja) widget.c.alertas.janelaEmFoco = true;
    } else {
      widget.c.alertas.janelaEmFoco = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.c.aparencia;
    final cores = (a?['cores'] as Map?) ?? const {};
    final topo = (a?['topo'] as Map?) ?? const {};
    final news = (((a?['news'] as Map?)?['cores'] as List?) ?? const []).map((v) => corHex(v, const Color(0xFF993635))).toList();
    final claro = Paleta.de(cores['claro'] as Map?, topo['claro'] as Map?, Paleta.claroPadrao);
    final escuro = Paleta.de(cores['escuro'] as Map?, topo['escuro'] as Map?, Paleta.escuroPadrao);
    return MaterialApp(
      navigatorKey: navegador,
      title: AppConfig.nome,
      debugShowCheckedModeBanner: false,
      theme: temaDe(claro, Brightness.light, news),
      darkTheme: temaDe(escuro, Brightness.dark, news),
      themeMode: widget.c.escuro ? ThemeMode.dark : ThemeMode.light,
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: ListenableBuilder(
        listenable: widget.c,
        builder: (_, __) => switch (widget.c.fase) {
          Fase.iniciando => const TelaCarregando(),
          Fase.login => TelaLogin(widget.c),
          Fase.bloqueado => TelaBloqueio(widget.c),
          Fase.pronto => Casca(widget.c, widget.atualizador, aoMinimizar: _bandeja),
        },
      ),
    );
  }
}

/// O ícone ao lado do relógio e o menu dele.
class Bandeja with TrayListener {
  final Controle c;
  Bandeja(this.c);
  int? _ultimo;

  Future<void> iniciar() async {
    trayManager.addListener(this);
    await _icone();
    await _menu();
    c.addListener(() async {
      final n = c.naoLidas + c.comunicados.length;
      if (n != _ultimo) {
        _ultimo = n;
        try {
          await _icone();
          await _menu();
        } catch (_) {}
      }
    });
  }

  Future<void> _icone() async {
    final est = (c.naoLidas + c.comunicados.length) > 0 ? 'msg' : 'ok';
    if (Platform.isMacOS) {
      // Sem novidade: o balão em silhueta, que acompanha a barra de menus clara ou
      // escura (template). Com mensagem: o balão COLORIDO com a bolinha VERMELHA —
      // uma imagem template sai numa cor só, e a bolinha não chamaria atenção.
      await trayManager.setIcon('assets/bandeja/mac_$est.png', isTemplate: est == 'ok');
      // O número em vermelho no ícone do Dock (quando a janela está aberta).
      try {
        await windowManager.setBadgeLabel(c.naoLidas > 0 ? (c.naoLidas > 99 ? '99+' : '${c.naoLidas}') : '');
      } catch (_) {}
    } else if (Platform.isLinux) {
      await trayManager.setIcon('assets/bandeja/lin_$est.png');
    } else {
      await trayManager.setIcon('assets/bandeja/win_$est.ico');
    }
    if (Platform.isLinux) return;   // o AppIndicator não tem dica
    final n = c.naoLidas;
    await trayManager.setToolTip(n > 0 ? '${AppConfig.nome} — $n ${n == 1 ? 'mensagem não lida' : 'mensagens não lidas'}' : AppConfig.nome);
  }

  Future<void> _menu() async {
    await trayManager.setContextMenu(Menu(items: [
      MenuItem(key: 'abrir', label: 'Abrir o ${AppConfig.nome}'),
      if (c.naoLidas > 0) MenuItem(key: 'conversas', label: 'Conversas (${c.naoLidas} não ${c.naoLidas == 1 ? 'lida' : 'lidas'})'),
      MenuItem.separator(),
      MenuItem(key: 'sair', label: 'Sair do ${AppConfig.nome}'),
    ]));
  }

  @override
  void onTrayIconMouseDown() {
    if (Platform.isWindows) {
      _abrir();
    } else {
      trayManager.popUpContextMenu();
    }
  }

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  Future<void> _abrir() async {
    await Janela.mostrar();
    c.janelaVisivel = true;
    await c.acordou();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    switch (menuItem.key) {
      case 'abrir':
        await _abrir();
      case 'conversas':
        await _abrir();
        Casca.irPara(1);
      case 'sair':
        await _abrir();
        final ctx = navegador.currentContext;
        final sair = ctx == null || !ctx.mounted
            ? true
            : await showDialog<bool>(
                  context: ctx,
                  builder: (d) => AlertDialog(
                    title: Text('Sair do ${AppConfig.nome}?'),
                    content: const Text('Enquanto o app estiver fechado, você não recebe os comunicados nem os avisos de mensagem nova.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Continuar aberto')),
                      FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Sair')),
                    ],
                  ),
                ) ??
                false;
        if (!sair) return;
        try {
          await trayManager.destroy();
        } catch (_) {}
        await InstanciaUnica.liberar();
        await windowManager.setPreventClose(false);
        exit(0);
    }
  }
}
