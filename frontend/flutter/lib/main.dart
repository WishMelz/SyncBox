import 'dart:io';

import 'package:flutter/material.dart';

import 'app.dart';
import 'core/storage/session_store.dart';
import 'features/connection/connection_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final connection = ConnectionController(
    store: SecureSessionStore(),
    platform: Platform.isAndroid
        ? 'android'
        : Platform.isWindows
        ? 'windows'
        : 'other',
  );
  runApp(SyncBoxApp(connection: connection));
  connection.restore();
}
