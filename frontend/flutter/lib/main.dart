import 'dart:io';

import 'package:flutter/material.dart';

import 'app.dart';
import 'core/storage/session_store.dart';
import 'features/connection/connection_controller.dart';
import 'platform/windows_tray.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final connection = ConnectionController(
    store: SecureSessionStore(),
    platform: Platform.isAndroid
        ? 'android'
        : Platform.isWindows
        ? 'windows'
        : 'other',
  );
  if (Platform.isWindows) {
    try {
      await WindowsTrayController.initialize();
    } catch (error) {
      // A tray integration failure must not prevent the normal workspace from
      // starting. The next Windows build can still be used as a regular app.
      debugPrint('Windows tray unavailable: $error');
    }
  }
  runApp(SyncBoxApp(connection: connection));
  connection.restore();
}
