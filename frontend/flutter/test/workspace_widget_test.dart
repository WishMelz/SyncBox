import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:syncbox/app.dart';
import 'package:syncbox/core/network/api_client.dart';
import 'package:syncbox/features/connection/connection_controller.dart';

import 'support.dart';

void main() {
  for (final size in [const Size(360, 640), const Size(390, 844)]) {
    testWidgets(
      'mobile tabs keep settings and hide inside a conversation at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var settingsReads = 0;
        final pendingSettings = Completer<http.Response>();
        final api = ApiClient(
          Uri.parse('https://example.com'),
          client: MockClient((r) async {
            if (r.url.path.endsWith('/settings')) {
              settingsReads++;
              return pendingSettings.future;
            }
            if (r.url.path.endsWith('/messages')) {
              return http.Response('{"items":[],"page":1,"totalPages":0}', 200);
            }
            return http.Response(
              '{"items":[{"id":"one","title":"Temporary","preview":"Sample","messageCount":1}],"page":1,"totalPages":1}',
              200,
            );
          }),
        )..token = 'token';
        final connection =
            ConnectionController(store: MemoryStore(), platform: 'android')
              ..api = api
              ..serverText = 'https://example.com'
              ..username = 'owner'
              ..deviceName = 'Android'
              ..stage = ConnectionStage.workspace;
        await tester.pumpWidget(SyncBoxApp(connection: connection));
        await tester.pumpAndSettle();
        expect(find.text('消息列表'), findsOneWidget);
        expect(find.text('SyncBox'), findsNothing);
        expect(find.byTooltip('新建会话'), findsOneWidget);
        expect(find.byType(NavigationBar), findsOneWidget);

        await tester.tap(find.byIcon(Icons.settings_outlined));
        await tester.pump();
        await tester.pump();
        expect(find.text('账号与连接'), findsOneWidget);
        // Leaving an in-flight settings operation must not discard its result.
        await tester.tap(find.byIcon(Icons.chat_bubble_outline));
        await tester.pump();
        expect(
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .selectedIndex,
          1,
        );
        pendingSettings.complete(
          http.Response(
            jsonEncode({
              'cleanup': {'enabled': false, 'idleDays': 30},
              'storage': {'fileCount': 0, 'bytes': 0},
              'twoFactorEnabled': false,
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        );
        await tester.pumpAndSettle();
        final name = find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == '设备名称',
        );
        await tester.ensureVisible(name);
        await tester.enterText(name, 'Unsubmitted device name');
        await tester.tap(find.byIcon(Icons.chat_bubble_outline));
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.settings_outlined));
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(name).controller!.text,
          'Unsubmitted device name',
        );
        expect(settingsReads, 1);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.text('消息列表'), findsOneWidget);
        await tester.tap(find.text('Temporary'));
        await tester.pumpAndSettle();
        expect(find.byType(NavigationBar), findsNothing);
        expect(find.text('消息列表'), findsNothing);
        expect(find.byType(AppBar), findsNothing);
        expect(find.byTooltip('返回会话列表'), findsOneWidget);
        await tester.tap(find.byTooltip('返回会话列表'));
        await tester.pumpAndSettle();
        expect(find.byType(NavigationBar), findsOneWidget);
        expect(find.text('消息列表'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        connection.dispose();
        api.close();
      },
    );
  }

  for (final size in [const Size(390, 844), const Size(1280, 800)]) {
    testWidgets('workspace selection and send at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var sent = false;
      final api = ApiClient(
        Uri.parse('https://example.com'),
        client: MockClient((r) async {
          if (r.method == 'POST') {
            sent = true;
            return http.Response('{}', 201);
          }
          if (r.url.path.endsWith('/messages')) {
            return http.Response('{"items":[],"page":1,"totalPages":0}', 200);
          }
          return http.Response(
            '{"items":[{"id":"one","title":"Temporary","preview":"Sample","messageCount":1}],"page":1,"totalPages":1}',
            200,
          );
        }),
      )..token = 'token';
      final c = ConnectionController(store: MemoryStore(), platform: 'windows')
        ..api = api
        ..stage = ConnectionStage.workspace;
      await tester.pumpWidget(SyncBoxApp(connection: c));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Temporary'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('发送消息'), findsOneWidget);
      expect(
        find.byTooltip('返回会话列表'),
        size.width < 800 ? findsOneWidget : findsNothing,
      );
      await tester.enterText(
        find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.hintText == '发送文案或链接…',
        ),
        'Share between devices',
      );
      await tester.tap(find.byTooltip('发送消息'));
      await tester.pumpAndSettle();
      expect(sent, true);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
    });
  }
}
