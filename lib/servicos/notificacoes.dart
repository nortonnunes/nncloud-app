// Notificações do sistema (Central de Notificações no macOS, toast no Windows).
//
// ⚠️ No Windows o toast precisa de um AppUserModelID registrado no ATALHO do
// menu Iniciar — é o instalador que o cria (`instalador/windows/nncloud.iss`).
// Rodando sem instalar (flutter run), a notificação pode não aparecer.
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class Notificacoes {
  static const appUserModelId = 'NortonNunes.NNCloud';
  static const _guid = '6c1b9a52-7f3e-4b8e-9d2a-4f0c2e8b7a11';

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _pronto = false;
  int _id = 0;

  Future<void> iniciar({void Function()? aoTocar}) async {
    try {
      await _plugin.initialize(
        InitializationSettings(
          macOS: const DarwinInitializationSettings(requestAlertPermission: true, requestBadgePermission: false, requestSoundPermission: false),
          windows: WindowsInitializationSettings(appName: 'NN Cloud', appUserModelId: appUserModelId, guid: _guid),
        ),
        onDidReceiveNotificationResponse: (_) => aoTocar?.call(),
      );
      _pronto = true;
    } catch (_) {
      _pronto = false;   // sem notificação não é motivo para o app não abrir
    }
  }

  Future<void> mostrar(String titulo, String texto) async {
    if (!_pronto) return;
    try {
      await _plugin.show(
        ++_id,
        titulo,
        texto,
        NotificationDetails(
          macOS: const DarwinNotificationDetails(presentAlert: true, presentSound: false),
          windows: Platform.isWindows ? const WindowsNotificationDetails() : null,
        ),
      );
    } catch (_) {
      // notificação é aviso, nunca bloqueia a sincronização
    }
  }
}
