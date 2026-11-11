import 'dart:io';

import 'package:syncbox/core/network/api_client.dart';

/// Read-only connectivity check. Never creates the deployment's owner account.
Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln(
      'Usage: dart run tool/check_server.dart https://sync.example.com',
    );
    exitCode = 64;
    return;
  }
  ApiClient? api;
  try {
    api = ApiClient(normalizeServer(arguments.single));
    final health = await api.request('/health');
    final status = await api.request('/auth/status');
    stdout.writeln(
      'API: ${health['status']}; SQLite: ${health['database']}; initialized: ${status['initialized']}',
    );
  } catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  } finally {
    api?.close();
  }
}
