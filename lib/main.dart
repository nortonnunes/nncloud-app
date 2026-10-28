// NN Cloud — aplicativo de sincronização de pastas (Windows e macOS).
//
// Janela: fechar ESCONDE (o app segue na barra de menus / bandeja); "Sair" só
// pela bandeja. Aberto com `--oculto` (início com o sistema), começa escondido.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'config.dart';
import 'servicos/armazenamento.dart';
import 'servicos/controle.dart';
import 'servicos/notificacoes.dart';
import 'servicos/sistema.dart';
import 'tema.dart';
import 'telas/casca.dart';
import 'telas/conectar.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('pt_BR');
  final arm = Armazenamento();
  await arm.iniciar();

  final aba = ValueNotifier<int>(0);
  final unico = await InstanciaUnica.garantir(arm.dados, () async {
    await windowManager.show();
    await windowManager.focus();
  });
  if (!unico) exit(0);   // a outra cópia foi avisada e mostrou a janela

  await windowManager.ensureInitialized();
  final oculto = args.contains('--oculto');
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      size: Size(1000, 700),
      minimumSize: Size(820, 560),
      center: true,
      title: AppConfig.nome,
      titleBarStyle: TitleBarStyle.normal,
    ),
    () async {
      if (!oculto) {
        await windowManager.show();
        await windowManager.focus();
      }
    },
  );
  await windowManager.setPreventClose(true);

  final notif = Notificacoes();
  await notif.iniciar(aoTocar: () async {
    await windowManager.show();
    await windowManager.focus();
  });
  final c = Controle(arm, notif)..janelaVisivel = !oculto;
  final tema = ValueNotifier<ThemeMode>(ThemeMode.values.firstWhere((m) => m.name == arm.pref<String>('tema', 'system'), orElse: () => ThemeMode.system));

  runApp(AppNnCloud(c, tema, aba));
  await Bandeja(c, aba).iniciar();
  await c.iniciar();
}

class AppNnCloud extends StatefulWidget {
  final Controle c;
  final ValueNotifier<ThemeMode> tema;
  final ValueNotifier<int> aba;
  const AppNnCloud(this.c, this.tema, this.aba, {super.key});
  @override
  State<AppNnCloud> createState() => _AppNnCloudState();
}

class _AppNnCloudState extends State<AppNnCloud> with WindowListener {
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowClose() async {
    // Fechar esconde: a sincronização continua em segundo plano.
    await windowManager.hide();
    widget.c.janelaVisivel = false;
  }

  @override
  void onWindowFocus() => widget.c.janelaVisivel = true;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: widget.tema,
      builder: (_, modo, __) => MaterialApp(
        title: AppConfig.nome,
        debugShowCheckedModeBanner: false,
        theme: Tema.claro(),
        darkTheme: Tema.escuro(),
        themeMode: modo,
        locale: const Locale('pt', 'BR'),
        supportedLocales: const [Locale('pt', 'BR')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: ListenableBuilder(
          listenable: widget.c,
          builder: (_, __) => widget.c.situacao == Situacao.desconectado || (widget.c.situacao == Situacao.conectando && widget.c.eu == null)
              ? TelaConectar(widget.c)
              : Casca(widget.c, widget.tema, widget.aba),
        ),
      ),
    );
  }
}

/// O ícone na barra de menus (macOS) / bandeja (Windows) e o menu dele.
class Bandeja with TrayListener {
  final Controle c;
  final ValueNotifier<int> aba;
  Bandeja(this.c, this.aba);
  Situacao? _ultima;

  Future<void> iniciar() async {
    trayManager.addListener(this);
    await _icone();
    await _menu();
    c.addListener(() async {
      if (c.situacao != _ultima) {
        _ultima = c.situacao;
        await _icone();
        await _menu();
      }
    });
  }

  Future<void> _icone() async {
    final estado = switch (c.situacao) {
      Situacao.sincronizando || Situacao.conectando => 'sinc',
      Situacao.offline || Situacao.erro || Situacao.desconectado => 'alerta',
      Situacao.pausado => 'pausa',
      _ => 'ok',
    };
    if (Platform.isMacOS) {
      await trayManager.setIcon('assets/bandeja/mac_$estado.png', isTemplate: true);
    } else {
      await trayManager.setIcon('assets/bandeja/win_$estado.ico');
    }
    await trayManager.setToolTip('NN Cloud — ${switch (c.situacao) {
      Situacao.ok => 'em dia',
      Situacao.sincronizando => 'sincronizando',
      Situacao.offline => 'sem conexão',
      Situacao.pausado => 'pausado',
      Situacao.erro => 'precisa de atenção',
      Situacao.conectando => 'conectando',
      Situacao.desconectado => 'desconectado',
    }}');
  }

  Future<void> _menu() async {
    await trayManager.setContextMenu(Menu(items: [
      MenuItem(key: 'abrir', label: 'Abrir o NN Cloud'),
      MenuItem.separator(),
      MenuItem(key: 'sinc', label: 'Sincronizar agora', disabled: c.api == null),
      MenuItem(key: 'pausa', label: c.pausado ? 'Retomar' : 'Pausar', disabled: c.api == null),
      MenuItem.submenu(
        label: 'Abrir pasta',
        disabled: c.pares.isEmpty,
        submenu: Menu(items: [
          for (final pr in c.pares) MenuItem(key: 'pasta:${pr['id']}', label: (pr['nome'] as String?)?.isNotEmpty == true ? pr['nome'] as String : 'Pasta'),
        ]),
      ),
      MenuItem(key: 'web', label: 'Abrir no navegador', disabled: c.eu == null),
      MenuItem.separator(),
      MenuItem(key: 'sair', label: 'Sair do NN Cloud'),
    ]));
  }

  Future<void> _mostrar() async {
    await windowManager.show();
    await windowManager.focus();
    c.janelaVisivel = true;
  }

  @override
  void onTrayIconMouseDown() {
    if (Platform.isWindows) {
      _mostrar();
    } else {
      trayManager.popUpContextMenu();
    }
  }

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    final k = menuItem.key ?? '';
    switch (k) {
      case 'abrir':
        await _mostrar();
      case 'sinc':
        c.sincronizarAgora();
      case 'pausa':
        await c.pausar(!c.pausado);
        await _menu();
      case 'web':
        await c.abrirNavegador('${c.eu?['config']?['web'] ?? ''}');
      case 'sair':
        await trayManager.destroy();
        await InstanciaUnica.liberar();
        await windowManager.setPreventClose(false);
        exit(0);
      default:
        if (k.startsWith('pasta:')) {
          final pr = c.pares.where((x) => '${x['id']}' == k.substring(6)).firstOrNull;
          if (pr != null) await c.abrirPasta(pr['caminho_local'] as String);
        }
    }
  }
}
