import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:syncbox/core/network/api_client.dart';
import 'package:syncbox/features/workspace/widgets/conversation_detail.dart';
import 'package:syncbox/features/workspace/workspace_controller.dart';
import 'package:syncbox/features/workspace/workspace_repository.dart';
import 'package:syncbox/models/conversation.dart';

void main() {
  testWidgets('Ctrl+V stages a screenshot and still pastes ordinary text', (
    tester,
  ) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==',
    );
    var image = true;
    const channel = MethodChannel('syncbox/file-drop');
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => image ? png : null,
    );
    messenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async =>
          call.method == 'Clipboard.getData' ? {'text': 'plain'} : null,
    );
    final api = ApiClient(
      Uri.parse('https://example.com'),
      client: MockClient((_) async => http.Response('{}', 200)),
    );
    final c = WorkspaceController(
      WorkspaceRepository(api),
      onExpired: () async {},
    )..selected = const Conversation(id: 'one', title: '测试');
    addTearDown(() {
      c.dispose();
      api.close();
      messenger.setMockMethodCallHandler(channel, null);
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConversationDetail(
            controller: c,
            onRename: () {},
            onDelete: () {},
            compact: false,
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    Future<void> paste() async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
    }

    await paste();
    expect(c.imageDrafts['one'], png);
    expect(c.drafts['one'], isNull);
    image = false;
    await paste();
    expect(c.drafts['one'], 'plain');
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}
