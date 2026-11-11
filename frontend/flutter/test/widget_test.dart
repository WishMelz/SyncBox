import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:syncbox/app.dart';
import 'package:syncbox/core/network/api_client.dart';
import 'package:syncbox/features/connection/connection_controller.dart';

import 'support.dart';

void main() {
  for (final size in [const Size(390, 844), const Size(1280, 800)]) {
    testWidgets('connection and six-character setup validation at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var setups = 0;
      final c = ConnectionController(
        store: MemoryStore(),
        platform: 'android',
        factory: (uri) => ApiClient(
          uri,
          client: MockClient((r) async {
            if (r.url.path.endsWith('status')) {
              return http.Response('{"initialized":false}', 200);
            }
            setups++;
            return http.Response('{"message":"test setup reached"}', 409);
          }),
        ),
      );
      await tester.pumpWidget(SyncBoxApp(connection: c));
      await tester.enterText(
        find.byType(TextFormField).first,
        'https://example.com',
      );
      await tester.tap(find.text('连接服务'));
      await tester.pumpAndSettle();
      expect(find.text('首次设置私人空间'), findsOneWidget);
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'owner');
      await tester.enterText(fields.at(1), 'short');
      await tester.enterText(fields.at(2), 'short');
      await tester.ensureVisible(find.text('完成首次设置'));
      await tester.tap(find.text('完成首次设置'));
      await tester.pumpAndSettle();
      expect(setups, 0);
      expect(find.text('密码需为 6–128 位'), findsOneWidget);
      await tester.enterText(fields.at(1), 'six123');
      await tester.enterText(fields.at(2), 'six123');
      await tester.ensureVisible(find.text('完成首次设置'));
      await tester.tap(find.text('完成首次设置'));
      await tester.pumpAndSettle();
      expect(setups, 1);
      expect(find.text('登录个人空间'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
    });
  }
}
