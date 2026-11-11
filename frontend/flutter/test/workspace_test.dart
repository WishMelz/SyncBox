import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:syncbox/core/network/api_client.dart';
import 'package:syncbox/models/conversation.dart';
import 'package:syncbox/features/workspace/workspace_repository.dart';
import 'package:syncbox/features/workspace/workspace_controller.dart';

void main() {
  test(
    'late history response cannot replace the selected conversation',
    () async {
      final first = Completer<http.Response>();
      final api = ApiClient(
        Uri.parse('https://example.com'),
        client: MockClient((r) async {
          if (r.url.path.contains('/first/')) return first.future;
          return http.Response('{"items":[],"page":1,"totalPages":0}', 200);
        }),
      );
      final c = WorkspaceController(
        WorkspaceRepository(api),
        onExpired: () async {},
      );
      final pending = c.select(const Conversation(id: 'first', title: 'First'));
      await c.select(const Conversation(id: 'second', title: 'Second'));
      first.complete(
        http.Response(
          '{"items":[{"id":"old","content":"wrong conversation","createdAt":"2026-11-07T00:00:00Z","isStarred":false}],"page":1,"totalPages":1}',
          200,
        ),
      );
      await pending;
      expect(c.selected!.id, 'second');
      expect(c.messages, isEmpty);
      c.dispose();
      api.close();
    },
  );
  test('failed send preserves per-conversation draft', () async {
    final api = ApiClient(
      Uri.parse('https://example.com'),
      client: MockClient(
        (r) async => r.method == 'POST'
            ? http.Response('{"message":"offline"}', 503)
            : http.Response('{"items":[],"page":1,"totalPages":0}', 200),
      ),
    );
    final c = WorkspaceController(
      WorkspaceRepository(api),
      onExpired: () async {},
    );
    await c.select(const Conversation(id: 'one', title: 'One'));
    c.drafts['one'] = 'keep this';
    await c.send('keep this');
    expect(c.drafts['one'], 'keep this');
    expect(c.error, 'offline');
    c.dispose();
    api.close();
  });
  test(
    'delivered message is not retried when subsequent list refresh fails',
    () async {
      for (final failedPath in [
        '/api/v1/conversations',
        '/api/v1/conversations/one/messages',
      ]) {
        var sends = 0;
        final api = ApiClient(
          Uri.parse('https://example.com'),
          client: MockClient((r) async {
            if (r.method == 'POST') {
              sends++;
              return http.Response('{}', 201);
            }
            if (r.url.path == failedPath) {
              return http.Response('{"message":"offline"}', 503);
            }
            return http.Response('{"items":[],"page":1,"totalPages":0}', 200);
          }),
        );
        final c = WorkspaceController(
          WorkspaceRepository(api),
          onExpired: () async {},
        );
        c.selected = const Conversation(id: 'one', title: 'One');
        c.drafts['one'] = 'sent';
        await c.send('sent');
        expect(c.drafts.containsKey('one'), false);
        expect(c.error, '消息已发送，列表刷新失败，请刷新查看。');
        await c.refresh();
        expect(sends, 1);
        c.dispose();
        api.close();
      }
    },
  );

  test('refresh does not automatically send a failed draft', () async {
    var sends = 0;
    final api = ApiClient(
      Uri.parse('https://example.com'),
      client: MockClient((r) async {
        if (r.method == 'POST') {
          sends++;
          return http.Response('{"message":"offline"}', 503);
        }
        return http.Response('{"items":[],"page":1,"totalPages":0}', 200);
      }),
    );
    final c = WorkspaceController(
      WorkspaceRepository(api),
      onExpired: () async {},
    );
    c.selected = const Conversation(id: 'one', title: 'One');
    c.drafts['one'] = 'keep';
    await c.send('keep');
    await c.refresh();
    await c.refresh();
    expect(c.drafts['one'], 'keep');
    expect(sends, 1);
    await c.send('keep');
    expect(sends, 2);
    c.dispose();
    api.close();
  });
}
