import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'features/connection/connection_controller.dart';
import 'features/connection/connection_page.dart';
import 'features/workspace/workspace_page.dart';

class SyncBoxApp extends StatelessWidget {
  const SyncBoxApp({super.key, required this.connection});
  final ConnectionController connection;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'SyncBox',
    debugShowCheckedModeBanner: false,
    locale: const Locale('zh', 'CN'),
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff1678ae)),
      scaffoldBackgroundColor: const Color(0xffe7eef3),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
    ),
    home: ListenableBuilder(
      listenable: connection,
      builder: (context, _) => connection.stage == ConnectionStage.workspace
          ? WorkspacePage(key: ValueKey(connection.api), connection: connection)
          : ConnectionPage(
              key: ValueKey('${connection.stage}:${connection.serverText}'),
              connection: connection,
            ),
    ),
  );
}
