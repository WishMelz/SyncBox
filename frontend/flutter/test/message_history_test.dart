import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:syncbox/core/network/api_client.dart';
import 'package:syncbox/features/workspace/workspace_controller.dart';
import 'package:syncbox/features/workspace/workspace_repository.dart';
import 'package:syncbox/models/conversation.dart';

void main() {
  test('cursor history retains reading windows, handles mutations and manual retry', () async {
    final records = List.generate(
      9,
      (n) => {
        'id': '$n'.padLeft(3, '0'),
        'content': '消息 $n',
        'createdAt': '2026-11-09T00:00:00.000Z',
        'isStarred': false,
      },
    );
    final calls = <Map<String, String>>[];
    var fail = false;
    final api = ApiClient(
      Uri.parse('https://fixture.example'),
      client: MockClient((r) async {
        if (r.url.path == '/api/v1/conversations') {
          return http.Response('{"items":[],"page":1,"totalPages":0}', 200);
        }
        final params = r.url.queryParameters;
        calls.add(params);
        if (fail) return http.Response('{"message":"offline"}', 503);
        final range = records.reversed.where((m) {
          final cursor = '${m['createdAt']}|${m['id']}';
          return (params['before'] == null ||
                  cursor.compareTo(params['before']!) < 0) &&
              (params['since'] == null ||
                  cursor.compareTo(params['since']!) >= 0);
        }).toList();
        final items = range.take(3).toList();
        return http.Response(
          jsonEncode({
            'items': items,
            'total': records.length,
            'page': 1,
            'totalPages': 3,
            'hasMore': range.length > 3,
            'nextCursor': range.length > 3
                ? '${items.last['createdAt']}|${items.last['id']}'
                : null,
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final c = WorkspaceController(
      WorkspaceRepository(api),
      onExpired: () async {},
    );
    await c.select(const Conversation(id: 'a', title: 'A'));
    expect(c.messages.map((m) => m.id), ['008', '007', '006']);
    c.messageHistory.scrollOffset = 400;
    fail = true;
    await c.loadOlderMessages();
    expect(c.messages.length, 3);
    expect(c.messageHistory.olderError, isNotNull);
    fail = false;
    records.removeWhere((m) => m['id'] == '006');
    records.add({
      'id': '009',
      'content': '新增',
      'createdAt': '2026-11-09T00:00:00.000Z',
      'isStarred': false,
    });
    await Future.wait([
      c.loadOlderMessages(),
      c.loadOlderMessages(),
      c.refresh(),
    ]);
    expect(c.messages.map((m) => m.id), [
      '009',
      '008',
      '007',
      '005',
      '004',
      '003',
    ]);
    expect(c.messageHistory.olderError, isNull);
    await c.select(const Conversation(id: 'b', title: 'B'));
    await c.select(const Conversation(id: 'a', title: 'A'));
    expect(c.messages.length, 6);
    expect(c.messageHistory.scrollOffset, 400);
    await c.loadOlderMessages();
    expect(c.messageHistory.hasOlder, isFalse);
    expect(c.messages.map((m) => m.id).toSet().length, 9);
    expect(calls.any((p) => p['since'] != null && p['before'] != null), isTrue);
    fail = true;
    await c.refresh();
    expect(c.messages.length, 9);
    c.dispose();
    api.close();
  });
}
