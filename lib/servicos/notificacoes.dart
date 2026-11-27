// Notificações do sistema (Central de Notificações no macOS, toast no Windows,
// o servidor de notificações da sessão no Linux — GNOME, KDE, XFCE…).
//
// ⚠️ No Windows o toast precisa de um AppUserModelID registrado no ATALHO do
// menu Iniciar — é o instalador que o cria (`instalador/windows/conversas.iss`).
// Rodando sem instalar (flutter run), a notificação pode não aparecer.
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../config.dart';

class Notificacoes {
  static const appUserModelId = 'NortonNunes.NNConversas';
  static const _guid = '4eab86b0-de42-4fde-969b-3f9b76296a36';

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _pronto = false;
  int _id = 0;

  /// [aoTocar] recebe o `payload` da notificação tocada (ex.: 'conversa:12').
  Future<void> iniciar({void Function(String? payload)? aoTocar}) async {
    // Linux: as notificações vão pelo barramento D-Bus da SESSÃO. Sem ele (app rodando
    // como root/sudo, sessão sem D-Bus, servidor sem desktop) o plugin falha FORA do
    // try — numa escuta assíncrona — e o erro aparece solto no terminal. Sem barramento,
    // o app segue sem notificação.
    if (Platform.isLinux && !_temBarramentoDaSessao()) {
      _pronto = false;
      return;
    }
    try {
      await _plugin.initialize(
        InitializationSettings(
          macOS: const DarwinInitializationSettings(requestAlertPermission: true, requestBadgePermission: true, requestSoundPermission: false),
          windows: WindowsInitializationSettings(appName: AppConfig.nome, appUserModelId: appUserModelId, guid: _guid),
          linux: const LinuxInitializationSettings(defaultActionName: 'Abrir o ${AppConfig.nome}'),
        ),
        onDidReceiveNotificationResponse: (r) => aoTocar?.call(r.payload),
      );
      _pronto = true;
    } catch (_) {
      _pronto = false;   // sem notificação não é motivo para o app não abrir
    }
  }

  static bool _temBarramentoDaSessao() {
    try {
      final end = Platform.environment['DBUS_SESSION_BUS_ADDRESS'] ?? '';
      String? caminho;
      if (end.isEmpty) {
        final uid = (Process.runSync('id', ['-u']).stdout as String).trim();
        caminho = '/run/user/$uid/bus';
      } else {
        final m = RegExp(r'unix:path=([^,;]+)').firstMatch(end);
        if (m == null) return true;   // abstract/tcp: deixa o plugin tentar
        caminho = m.group(1);
      }
      return caminho != null && FileSystemEntity.typeSync(caminho) != FileSystemEntityType.notFound;
    } catch (_) {
      return false;
    }
  }

  Future<void> mostrar(String titulo, String texto, {String? payload}) async {
    if (!_pronto) return;
    try {
      await _plugin.show(
        ++_id,
        titulo,
        texto,
        NotificationDetails(
          macOS: const DarwinNotificationDetails(presentAlert: true, presentSound: false),
          windows: Platform.isWindows ? const WindowsNotificationDetails() : null,
          linux: Platform.isLinux ? const LinuxNotificationDetails() : null,
        ),
        payload: payload,
      );
    } catch (_) {
      // notificação é aviso, nunca bloqueia o app
    }
  }
}
