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

  void invalidate() => bytes.add(
    utf8.encode(
      'event: sync\ndata: {"type":"invalidate","scope":"messages"}\n\n',
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
    events.last.invalidate();
    events.last.invalidate();
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
            XFile.fromData(Uint8List.fromList([1, 2, 3]), name: 'one.txt'),
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
            XFile.fromData(Uint8List.fromList([1, 2, 3]), name: 'one.txt'),
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
}
