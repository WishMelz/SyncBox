import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:file_selector/file_selector.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:syncbox/core/network/api_client.dart';
import 'package:syncbox/features/workspace/workspace_controller.dart';
import 'package:syncbox/features/workspace/workspace_repository.dart';
import 'package:syncbox/features/workspace/widgets/conversation_detail.dart';
import 'package:syncbox/features/workspace/widgets/conversation_list.dart';
import 'package:syncbox/features/workspace/widgets/message_card.dart';
import 'package:syncbox/models/conversation.dart';
import 'package:syncbox/models/message.dart';
import 'package:syncbox/shared/widgets/highlight_text.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final size in [const Size(390, 844), const Size(1280, 800)]) {
    testWidgets('message menu and search rendering at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = call.arguments['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      const body = '😀 SyncBOX https://example.com/SyncBOX?q=a+b';
      final note = '${List.filled(18, '批注内容').join(' ')}\nSyncBOX 命中尾部';
      var stars = 0, notes = 0, deletes = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.windows),
          home: Scaffold(
            body: SingleChildScrollView(
              child: MessageCard(
                own: true,
                message: Message(
                  id: 'm',
                  content: body,
                  createdAt: DateTime(2026, 11, 9, 19, 4),
                  device: '当前设备',
                  starred: false,
                  annotation: note,
                ),
                query: 'syncbox',
                onStar: () => stars++,
                onAnnotate: () => notes++,
                onDelete: () => deletes++,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('展开批注'), findsNothing);
      final renderedNote = tester.widget<Text>(
        find.descendant(
          of: find.byWidgetPredicate(
            (w) => w is HighlightText && w.text == note,
          ),
          matching: find.byType(Text),
        ),
      );
      expect(renderedNote.maxLines, isNull);
      final bodyFinder = find.byWidgetPredicate(
        (w) => w is HighlightText && w.text == body,
      );
      final text = tester.widget<Text>(
        find.descendant(of: bodyFinder, matching: find.byType(Text)),
      );
      expect(text.textSpan!.toPlainText(), body);
      expect(
        (text.textSpan! as TextSpan).children!.whereType<TextSpan>().where(
          (span) => span.style?.backgroundColor != null,
        ),
        isNotEmpty,
      );
      await tester.longPress(bodyFinder);
      await tester.pumpAndSettle();
      await tester.tap(find.text('复制内容'));
      await tester.pumpAndSettle();
      expect(copied, body);
      expect(find.text('已复制'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      final mouse = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await mouse.down(tester.getCenter(bodyFinder));
      await mouse.up();
      await tester.pumpAndSettle();
      await tester.tap(find.text('收藏'));
      await tester.pumpAndSettle();
      expect(stars, 1);
      await tester.tap(find.byTooltip('更多操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('编辑批注'));
      await tester.pumpAndSettle();
      expect(notes, 1);
      expect(deletes, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('highlighted URL opens its unchanged target', (tester) async {
    String? opened;
    const channel = MethodChannel('syncbox/links');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      opened = call.arguments as String;
      return true;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HighlightText(
            'https://example.com/SyncBOX?q=a+b。',
            query: 'syncbox',
            links: true,
          ),
        ),
      ),
    );
    final text = tester.widget<Text>(
      find.descendant(
        of: find.byType(HighlightText),
        matching: find.byType(Text),
      ),
    );
    final spans = (text.textSpan! as TextSpan).children!.whereType<TextSpan>();
    final matchedLink = spans.firstWhere(
      (s) => s.style?.backgroundColor != null,
    );
    (matchedLink.recognizer! as TapGestureRecognizer).onTap!();
    await tester.pumpAndSettle();
    expect(opened, 'https://example.com/SyncBOX?q=a+b');
  });

  testWidgets(
    'attachment matches stay visible and conversation menus target the row',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = ApiClient(
        Uri.parse('https://example.com'),
        client: MockClient(
          (_) async =>
              http.Response('{"items":[],"page":1,"totalPages":0}', 200),
        ),
      );
      final c =
          WorkspaceController(WorkspaceRepository(api), onExpired: () async {})
            ..conversations = [
              const Conversation(id: 'row', title: 'SyncBOX 会话'),
            ]
            ..conversationSearch = 'syncbox';
      String? renamed;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConversationList(
              controller: c,
              onCreate: () {},
              onRename: (row) => renamed = row.id,
            ),
          ),
        ),
      );
      final title = find.byWidgetPredicate(
        (w) => w is HighlightText && w.text == 'SyncBOX 会话',
      );
      await tester.longPress(title);
      await tester.pumpAndSettle();
      expect(find.text('置顶'), findsOneWidget);
      await tester.tap(find.text('重命名'));
      await tester.pumpAndSettle();
      expect(renamed, 'row');
      const filename = '很长的附件名称_SyncBOX_资料文件.txt';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageCard(
              message: Message(
                id: 'file',
                content: '[附件] $filename',
                createdAt: DateTime(2026),
                device: '另一台设备',
                starred: false,
                attachments: const [
                  Attachment(id: 'f', name: filename, size: 123),
                ],
              ),
              query: 'syncbox',
              api: api,
              onStar: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final file = tester.widget<HighlightText>(
        find.byWidgetPredicate((w) => w is HighlightText && w.text == filename),
      );
      expect(file.maxLines, isNull);
      expect(
        find.byWidgetPredicate(
          (w) => w is HighlightText && w.text.startsWith('[附件]'),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
      api.close();
    },
  );

  testWidgets('compact composer, attachment menu, and search shortcuts', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 340);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = ApiClient(
      Uri.parse('https://example.com'),
      client: MockClient(
        (_) async => http.Response('{"items":[],"page":1,"totalPages":0}', 200),
      ),
    );
    final c = WorkspaceController(
      WorkspaceRepository(api),
      onExpired: () async {},
    )..selected = const Conversation(id: 'c', title: '会话');
    c.fileDrafts['c'] = List.generate(
      5,
      (i) => XFile.fromData(Uint8List.fromList([1]), name: '文件$i.txt'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(title: const Text('SyncBox')),
          body: ListenableBuilder(
            listenable: c,
            builder: (_, _) => ConversationDetail(
              controller: c,
              compact: true,
              onRename: () {},
              onDelete: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    await tester.tap(find.byTooltip('添加图片或文件'));
    await tester.pumpAndSettle();
    expect(find.text('选择图片'), findsOneWidget);
    expect(find.text('选择文件'), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    final search = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == '搜索消息、批注或文件名',
    );
    expect(search, findsOneWidget);
    await tester.enterText(search, '关键词');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(c.messageSearch, '关键词');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(c.messageSearch, isEmpty);
    expect(search, findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
    api.close();
  });
}
