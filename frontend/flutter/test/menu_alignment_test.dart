import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:syncbox/core/network/api_client.dart';
import 'package:syncbox/features/workspace/widgets/conversation_list.dart';
import 'package:syncbox/features/workspace/widgets/message_card.dart';
import 'package:syncbox/features/workspace/workspace_controller.dart';
import 'package:syncbox/features/workspace/workspace_repository.dart';
import 'package:syncbox/models/conversation.dart';
import 'package:syncbox/models/message.dart';

void main() {
  for (final width in [390.0, 1280.0]) {
    for (final own in [false, true]) {
      testWidgets('more stays beside a short bubble: $width own=$own', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: TargetPlatform.windows),
            home: Scaffold(
              body: MessageCard(
                own: own,
                message: Message(
                  id: 'm',
                  content: '短消息',
                  createdAt: DateTime(2026),
                  device: '电脑',
                  starred: false,
                ),
                onStar: () {},
              ),
            ),
          ),
        );
        final bubble = tester.getRect(
          find.byWidgetPredicate((w) => w is Material && w.elevation == 1),
        );
        final icon = tester.getRect(find.byIcon(Icons.more_horiz));
        expect(bubble.width, lessThan(200));
        final gap = own ? bubble.left - icon.right : icon.left - bubble.right;
        expect(gap, inInclusiveRange(0, 24));
        expect((icon.center.dy - bubble.center.dy).abs(), lessThan(1));
        await tester.tap(find.byTooltip('更多操作'));
        await tester.pumpAndSettle();
        final opacity = tester.widget<Opacity>(
          find
              .ancestor(
                of: find.byTooltip('更多操作'),
                matching: find.byType(Opacity),
              )
              .first,
        );
        expect(opacity.opacity, 1);
        await tester.tapAt(const Offset(5, 500));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('selected conversation has one high contrast more icon', (
    tester,
  ) async {
    final api = ApiClient(
      Uri.parse('https://example.com'),
      client: MockClient(
        (_) async => http.Response('{"items":[],"page":1,"totalPages":0}', 200),
      ),
    );
    final controller =
        WorkspaceController(WorkspaceRepository(api), onExpired: () async {})
          ..conversations = [
            const Conversation(id: 'selected', title: '已选会话'),
            const Conversation(id: 'other', title: '其他会话'),
          ]
          ..selected = const Conversation(id: 'selected', title: '已选会话');
    addTearDown(() {
      controller.dispose();
      api.close();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConversationList(controller: controller, onCreate: () {}),
        ),
      ),
    );
    final tile = find.byWidgetPredicate(
      (w) =>
          w is ListTile && w.selected && w.trailing is PopupMenuButton<String>,
    );
    final icon = tester.widget<Icon>(
      find.descendant(of: tile, matching: find.byIcon(Icons.more_horiz)),
    );
    final background = tester.widget<ListTile>(tile).selectedTileColor!;
    final contrast =
        (background.computeLuminance() + .05) /
        (icon.color!.computeLuminance() + .05);
    expect(contrast, greaterThan(4.5));
    expect(
      find.descendant(of: tile, matching: find.byType(PopupMenuButton<String>)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: tile, matching: find.byIcon(Icons.arrow_drop_down)),
      findsNothing,
    );
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    testWidgets('image secondary action and normal preview: $platform', (
      tester,
    ) async {
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACklEQVR4nGMAAQAABQABDQottAAAAABJRU5ErkJggg==',
      );
      var annotations = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: platform),
          home: Scaffold(
            body: MessageCard(
              message: Message(
                id: 'image',
                content: '[图片]',
                createdAt: DateTime(2026),
                device: '手机',
                starred: false,
                hasImage: true,
              ),
              loadImage: () async => png,
              onStar: () {},
              onAnnotate: () => annotations++,
              onDelete: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => precacheImage(
          MemoryImage(png),
          tester.element(find.byType(MessageCard)),
        ),
      );
      await tester.pumpAndSettle();
      final image = find.byType(PrivateMessageImage);
      if (platform == TargetPlatform.windows) {
        final mouse = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton,
        );
        await mouse.down(tester.getCenter(image));
        await mouse.up();
      } else {
        await tester.longPress(image);
      }
      await tester.pumpAndSettle();
      for (final action in ['复制内容', '收藏', '添加批注', '删除消息']) {
        expect(find.text(action), findsOneWidget);
      }
      await tester.tap(find.text('添加批注'));
      await tester.pumpAndSettle();
      expect(annotations, 1);
      await tester.tap(image);
      await tester.pumpAndSettle();
      expect(find.byTooltip('关闭图片'), findsOneWidget);
      await tester.tap(find.byTooltip('关闭图片'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
