import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:syncbox/core/network/api_client.dart';
import 'package:syncbox/core/network/sync_events.dart';
import 'package:syncbox/features/workspace/workspace_controller.dart';
import 'package:syncbox/features/workspace/workspace_repository.dart';
import 'package:syncbox/models/conversation.dart';

const emptyPage = '{"items":[],"page":1,"totalPages":0}';

class EventClient extends http.BaseClient {
  final bytes = StreamController<List<int>>();
  bool closed = false;
  http.BaseRequest? request;
  int status = 200;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    this.request = request;
    return http.StreamedResponse(
      bytes.stream,
      status,
      headers: {'content-type': 'text/event-stream'},
    );
  }

  void invalidate({
    String scope = 'messages',
    String? conversationId,
    String? messageId,
  }) => bytes.add(
    utf8.encode(
      'event: sync\ndata: ${jsonEncode({'type': 'invalidate', 'scope': scope, 'conversationId': ?conversationId, 'messageId': ?messageId})}\n\n',
    ),
  );
  @override
  void close() {
    closed = true;
    unawaited(bytes.close());
  }
}

void main() {
  test('SSE supports multiline data and ignores heartbeat/retry frames', () {
    final parser = SyncEventParser();
    final received = <Map<String, dynamic>>[];
    for (final line in [
      'retry: 3000',
      '',
      ': heartbeat',
      '',
      'event: sync',
      'data: {"type":"invalidate",',
      'data: "scope":"messages"}',
      '',
      'data: {"type":"invalidate","scope":"favorites"}',
      '',
    ]) {
      final event = parser.add(line);
      if (event != null) received.add(event);
    }
    expect(received.map((e) => e['scope']), ['messages', 'favorites']);
  });

  test(
    'SSE cancellation closes the socket without closing regular requests',
    () async {
      final events = EventClient();
      final api = ApiClient(
        Uri.parse('https://example.com'),
        client: MockClient((_) async => http.Response('{}', 200)),
        eventClientFactory: () => events,
      )..token = 'secret';
      final connection = api.events();
      final received = <Map<String, dynamic>>[];
      final subscription = connection.stream.listen(received.add);
      await Future<void>.delayed(Duration.zero);
      expect(events.request!.headers['Authorization'], 'Bearer secret');
      expect(events.request!.url.query, isEmpty);
      final payload = utf8.encode(
        'data: {"type":"invalidate","scope":"messages","conversationId":"中文"}\r\n\r\n',
      );
      for (final byte in payload) {
        events.bytes.add([byte]);
      }
      await Future<void>.delayed(Duration.zero);
      expect(received.last['conversationId'], '中文');
      await subscription.cancel();
      expect(events.closed, true);
      expect(await api.request('/conversations'), isEmpty);
      api.close();
    },
  );

  test('foreground lifecycle closes idle sockets, reconnects, and retains invalidations during refresh', () async {
    final events = <EventClient>[];
    Completer<http.Response>? delayed;
    var reads = 0;
    final api = ApiClient(
      Uri.parse('https://example.com'),
      client: MockClient((_) async {
        reads++;
        if (delayed != null) {
          final pending = delayed!;
          delayed = null;
          return pending.future;
        }
        return http.Response(emptyPage, 200);
      }),
      eventClientFactory: () {
        final client = EventClient();
        events.add(client);
        return client;
      },
    );
    final c = WorkspaceController(
      WorkspaceRepository(api),
      onExpired: () async {},
    );
    c.start();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await Future<void>.delayed(const Duration(milliseconds: 180));
    expect(c.realtimeConnected, true);
    expect(events.length, 1);
    final pending = Completer<http.Response>();
    delayed = pending;
    final refreshing = c.refresh();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final previousReads = reads;
    events.last.invalidate(scope: 'conversations');
    events.last.invalidate(scope: 'conversations');
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await Future<void>.delayed(const Duration(milliseconds: 180));
    pending.complete(http.Response(emptyPage, 200));
    await refreshing;
    await Future<void>.delayed(const Duration(milliseconds: 180));
    expect(reads, previousReads + 1);
    c.setActive(false);
    expect(events.single.closed, true);
    expect(c.realtimeConnected, false);
    c.setActive(true);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(events.length, 2);
    c.setActive(true);
    expect(events.length, 2);
    // A dropped connection reconnects after backoff, without waiting for a poll.
    await events.last.bytes.close();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(c.realtimeConnected, false);
    await Future<void>.delayed(const Duration(milliseconds: 3100));
    expect(events.length, 3);
    c.dispose();
    expect(events.every((e) => e.closed), true);
    api.close();
    await Future<void>.delayed(const Duration(milliseconds: 10));
  });

  testWidgets('401 on events expires the session once and stops reconnecting', (
    tester,
  ) async {
    var expired = 0, opened = 0;
    final api = ApiClient(
      Uri.parse('https://example.com'),
      client: MockClient((_) async => http.Response(emptyPage, 200)),
      eventClientFactory: () {
        opened++;
        return EventClient()..status = 401;
      },
    );
    final c = WorkspaceController(
      WorkspaceRepository(api),
      onExpired: () async {
        expired++;
      },
    );
    c.start();
    await tester.pump();
    await tester.pump(const Duration(seconds: 10));
    expect(expired, 1);
    expect(opened, 1);
    c.dispose();
    api.close();
  });

  for (final kind in ['text', 'image', 'files']) {
    test(
      '$kind retry reuses clientId, edited and subsequent sends get new IDs',
      () async {
        final ids = <String>[];
        var fail = true;
        final api = ApiClient(
          Uri.parse('https://example.com'),
          client: MockClient((r) async {
            if (r.method != 'POST') return http.Response(emptyPage, 200);
            if (kind == 'files') {
              expect(r.body, contains('["报告.txt"]'));
              expect(r.body, contains('filename="报告.txt"'));
            }
            ids.add(
              kind == 'text'
                  ? jsonDecode(r.body)['clientId'] as String
                  : RegExp('name="clientId"\r\n\r\n([^\r]+)')
                        .firstMatch(r.body)!
                        .group(1)!,
            );
            return fail
                ? http.Response('{"message":"offline"}', 503)
                : http.Response('{}', 201);
          }),
        );
        final c = WorkspaceController(
          WorkspaceRepository(api),
          onExpired: () async {},
        );
        c.selected = const Conversation(id: 'one', title: 'One');
        c.drafts['one'] = 'original';
        if (kind == 'image') {
          c.attachImage('one', Uint8List.fromList([1, 2, 3]));
        }
        if (kind == 'files') {
          c.attachFiles('one', [
            XFile.fromData(Uint8List.fromList([1, 2, 3]), path: '报告.txt'),
          ]);
        }
        await c.send('original');
        await c.send('original');
        expect(ids[0], ids[1]);
        expect(c.drafts['one'], 'original');
        fail = false;
        await c.send('edited');
        expect(ids[2], isNot(ids[1]));
        // Keep the same message type for a deliberate second send.
        if (kind == 'image') {
          c.attachImage('one', Uint8List.fromList([1, 2, 3]));
        }
        if (kind == 'files') {
          c.attachFiles('one', [
            XFile.fromData(Uint8List.fromList([1, 2, 3]), path: '报告.txt'),
          ]);
        }
        await c.send('edited');
        expect(ids[3], isNot(ids[2]));
        c.dispose();
        api.close();
      },
    );
  }

  test('new messages in the open conversation are marked read on refresh', () async {
    var unread = true, marked = 0;
    final api = ApiClient(
      Uri.parse('https://example.com'),
      client: MockClient((r) async {
        if (r.method == 'PATCH') {
          unread = false;
          marked++;
          return http.Response('', 204);
        }
        if (r.url.path.endsWith('/messages')) {
          return http.Response(
            '{"items":[{"id":"m","content":"hi","createdAt":"2026-11-09T00:00:00Z","isStarred":false,"isRead":${!unread}}],"page":1,"totalPages":1}',
            200,
          );
        }
        return http.Response(
          '{"items":[{"id":"one","title":"One","unreadCount":${unread ? 1 : 0}}],"page":1,"totalPages":1}',
          200,
        );
      }),
    );
    final c = WorkspaceController(
      WorkspaceRepository(api),
      onExpired: () async {},
    );
    c.selected = const Conversation(id: 'one', title: 'One');
    await c.refresh();
    expect(marked, 1);
    expect(c.selected!.unreadCount, 0);
    await c.refresh();
    expect(marked, 1);
    unread = true;
    await c.searchMessages('search');
    expect(marked, 1);
    c.dispose();
    api.close();
  });

  test('routes SSE events by scope, conversationId, and messageId', () async {
    final events = <EventClient>[];
    final requests = <String>[];
    var messageContent = 'initial';
    var messageDeleted = false;
    final api = ApiClient(
      Uri.parse('https://example.com'),
      client: MockClient((r) async {
        requests.add('${r.method} ${r.url.path}');
        if (r.url.path == '/api/v1/conversations') {
          return http.Response(
            '{"items":[{"id":"one","title":"One"}],"page":1,"totalPages":1}',
            200,
          );
        }
        if (r.url.path == '/api/v1/conversations/one/messages') {
          return http.Response(
            jsonEncode({
              'items': messageDeleted
                  ? []
                  : [
                      {
                        'id': 'm1',
                        'content': messageContent,
                        'createdAt': '2026-11-09T00:00:00.000Z',
                        'isStarred': false,
                        'conversationId': 'one',
                      },
                    ],
              'page': 1,
              'totalPages': 1,
              'total': messageDeleted ? 0 : 1,
            }),
            200,
          );
        }
        if (r.url.path == '/api/v1/messages/m1') {
          if (messageDeleted) {
            return http.Response('{"message":"not found"}', 404);
          }
          return http.Response(
            jsonEncode({
              'id': 'm1',
              'content': messageContent,
              'createdAt': '2026-11-09T00:00:00.000Z',
              'isStarred': false,
              'conversationId': 'one',
            }),
            200,
          );
        }
        return http.Response(emptyPage, 200);
      }),
      eventClientFactory: () {
        final client = EventClient();
        events.add(client);
        return client;
      },
    );
    final c = WorkspaceController(
      WorkspaceRepository(api),
      onExpired: () async {},
    );
    await c.select(const Conversation(id: 'one', title: 'One'));
    c.start();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    requests.clear();

    // Unrelated conversation message event -> 0 history or detail requests.
    events.last.invalidate(
      scope: 'messages',
      conversationId: 'other',
      messageId: 'm2',
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(requests, isEmpty);

    // Selected conversation messageId update -> 1 GET /messages/m1.
    messageContent = 'updated';
    events.last.invalidate(
      scope: 'messages',
      conversationId: 'one',
      messageId: 'm1',
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(requests, ['GET /api/v1/messages/m1']);
    expect(c.messages.single.content, 'updated');
    requests.clear();

    // Selected conversation messageId deletion -> 404 removes local item.
    messageDeleted = true;
    events.last.invalidate(
      scope: 'messages',
      conversationId: 'one',
      messageId: 'm1',
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(requests, ['GET /api/v1/messages/m1']);
    expect(c.messages, isEmpty);

    c.dispose();
    api.close();
  });

  test('SSE reconnect reconciles loaded history pages', () async {
    final events = <EventClient>[];
    final historyQueries = <Map<String, String>>[];
    var oldMessageDeleted = false;
    final api = ApiClient(
      Uri.parse('https://example.com'),
      client: MockClient((r) async {
        if (r.url.path == '/api/v1/conversations') {
          return http.Response(
            '{"items":[{"id":"one","title":"One"}],"page":1,"totalPages":1}',
            200,
          );
        }
        if (r.url.path == '/api/v1/conversations/one/messages') {
          historyQueries.add(r.url.queryParameters);
          final items = [
            {
              'id': 'm2',
              'content': 'new',
              'createdAt': '2026-11-09T00:00:01.000Z',
              'isStarred': false,
            },
            if (!oldMessageDeleted)
              {
                'id': 'm1',
                'content': 'old',
                'createdAt': '2026-11-09T00:00:00.000Z',
                'isStarred': false,
              },
          ];
          return http.Response(
            jsonEncode({
              'items': items,
              'page': 1,
              'totalPages': 1,
              'total': items.length,
            }),
            200,
          );
        }
        return http.Response(emptyPage, 200);
      }),
      eventClientFactory: () {
        final client = EventClient();
        events.add(client);
        return client;
      },
    );
    final c = WorkspaceController(
      WorkspaceRepository(api),
      onExpired: () async {},
    );
    await c.select(const Conversation(id: 'one', title: 'One'));
    c.start();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(c.messages.map((m) => m.id), ['m2', 'm1']);

    historyQueries.clear();
    oldMessageDeleted = true;
    await events.last.bytes.close();
    await Future<void>.delayed(const Duration(milliseconds: 3500));
    expect(events.length, 2);
    expect(historyQueries.any((q) => q['since'] != null), isTrue);
    expect(c.messages.map((m) => m.id), ['m2']);

    c.dispose();
    api.close();
  });

  test('cancelling upload preserves drafts without setting error', () async {
    final started = Completer<void>();
    final gate = Completer<http.Response>();
    final api = ApiClient(
      Uri.parse('https://example.com'),
      client: MockClient((_) async => http.Response(emptyPage, 200)),
      uploadClientFactory: () => MockClient.streaming((request, bodyStream) async {
        unawaited(bodyStream.drain<void>());
        if (!started.isCompleted) started.complete();
        final res = await gate.future;
        return http.StreamedResponse(
          Stream<List<int>>.value(utf8.encode(res.body)),
          res.statusCode,
        );
      }),
    );
    final c = WorkspaceController(
      WorkspaceRepository(api),
      onExpired: () async {},
    );
    c.selected = const Conversation(id: 'one', title: 'One');
    c.drafts['one'] = 'keep';
    c.attachFiles('one', [
      XFile.fromData(Uint8List.fromList([1, 2, 3]), path: 'doc.txt'),
    ]);
    final future = c.send('keep');
    await started.future;
    expect(c.uploadProgress, isNotNull);
    c.cancelUpload();
    gate.complete(http.Response('{}', 500));
    await future;
    expect(c.error, isNull);
    expect(c.uploadProgress, isNull);
    expect(c.drafts['one'], 'keep');
    expect(c.fileDrafts['one']?.length, 1);
    c.dispose();
    api.close();
  });
}
