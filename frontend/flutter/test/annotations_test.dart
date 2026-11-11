import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:syncbox/core/network/api_client.dart';
import 'package:syncbox/features/workspace/workspace_repository.dart';
import 'package:syncbox/features/workspace/widgets/annotation_dialog.dart';
import 'package:syncbox/models/message.dart';

final message = Message(
  id: 'note-message',
  content: '原始内容',
  createdAt: DateTime(2026),
  device: '手机',
  starred: false,
  annotation: '旧批注',
);
void main() {
  test(
    'annotation decoding is backward compatible and updates via PATCH',
    () async {
      final old = {
        'id': 'm',
        'content': '正文',
        'createdAt': '2026-11-07T00:00:00Z',
        'isStarred': false,
      };
      expect(Message.fromJson(old).annotation, '');
      expect(
        Message.fromJson({...old, 'annotation': '可搜索备注'}).annotation,
        '可搜索备注',
      );
      final api = ApiClient(
        Uri.parse('https://example.com'),
        client: MockClient((r) async {
          expect(r.method, 'PATCH');
          expect(r.url.path, '/api/v1/messages/note-message');
          expect(jsonDecode(r.body), {'annotation': '新批注'});
          return http.Response('{}', 200);
        }),
      );
      await WorkspaceRepository(api).annotate(message, ' 新批注 ');
      api.close();
    },
  );
  testWidgets('failed save preserves draft and retry closes the editor', (
    tester,
  ) async {
    var attempts = 0;
    String? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => AnnotationDialog(
                  message: message,
                  onSave: (text) async {
                    attempts++;
                    if (attempts == 1) {
                      throw const ApiException('离线，请重试');
                    }
                    saved = text;
                  },
                ),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '新的批注草稿');
    await tester.pump();
    await tester.tap(find.text('保存批注'));
    await tester.pumpAndSettle();
    expect(find.text('离线，请重试'), findsOneWidget);
    expect(find.text('新的批注草稿'), findsOneWidget);
    await tester.tap(find.text('保存批注'));
    await tester.pumpAndSettle();
    expect(saved, '新的批注草稿');
    expect(find.byType(AnnotationDialog), findsNothing);
  });
  testWidgets('removing an annotation requires a separate confirmation', (
    tester,
  ) async {
    String? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: AnnotationDialog(
          message: message,
          onSave: (text) async {
            saved = text;
          },
        ),
      ),
    );
    await tester.tap(find.text('删除批注'));
    await tester.pump();
    expect(saved, isNull);
    expect(find.text('确认删除批注'), findsOneWidget);
  });
}
