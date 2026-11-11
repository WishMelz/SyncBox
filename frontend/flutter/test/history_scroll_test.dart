import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:syncbox/core/network/api_client.dart';
import 'package:syncbox/features/workspace/workspace_controller.dart';
import 'package:syncbox/features/workspace/workspace_repository.dart';
import 'package:syncbox/features/workspace/widgets/message_history_feed.dart';
import 'package:syncbox/models/conversation.dart';

void main() {
  for (final width in [390.0, 1280.0]) {
    testWidgets('history anchor, live arrivals, retry and restore at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 840);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final records = List.generate(
        96,
        (n) => {
          'id': '$n'.padLeft(3, '0'),
          'content': 'Message $n',
          'createdAt': '2026-11-09T00:00:00.000Z',
          'isStarred': false,
        },
      );
      var failOlder = false;
      final api = ApiClient(
        Uri.parse('https://fixture.example'),
        client: MockClient((r) async {
          if (!r.url.path.endsWith('/messages') || r.url.path.contains('/b/')) {
            return http.Response(
              '{"items":[],"total":0,"page":1,"totalPages":0}',
              200,
            );
          }
          final p = r.url.queryParameters;
          if (p['before'] != null && p['since'] == null) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
            if (failOlder) return http.Response('{"message":"offline"}', 503);
          }
          final range = records.reversed.where((m) {
            final c = '${m['createdAt']}|${m['id']}';
            return (p['before'] == null || c.compareTo(p['before']!) < 0) &&
                (p['since'] == null || c.compareTo(p['since']!) >= 0);
          }).toList();
          final items = range.take(30).toList();
          return http.Response(
            jsonEncode({
              'items': items,
              'page': 1,
              'totalPages': 4,
              'total': records.length,
              'hasMore': range.length > 30,
              'nextCursor': range.length > 30
                  ? '${items.last['createdAt']}|${items.last['id']}'
                  : null,
            }),
            200,
          );
        }),
      );
      final c = WorkspaceController(
        WorkspaceRepository(api),
        onExpired: () async {},
      );
      addTearDown(() {
        c.dispose();
        api.close();
      });
      await c.select(const Conversation(id: 'a', title: 'A'));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnimatedBuilder(
              animation: c,
              builder: (_, _) => c.selected?.id != 'a'
                  ? const SizedBox()
                  : MessageHistoryFeed(
                      key: ValueKey(c.historyKey),
                      controller: c,
                      itemBuilder: (_, n) {
                        final id = c.messages[n].id;
                        return SizedBox(
                          height: 80 + int.parse(id) % 5 * 15.0,
                          child: Align(
                            alignment: Alignment.topLeft,
                            child: Text('Row $id', key: ValueKey('row-$id')),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      ScrollPosition position() =>
          tester.state<ScrollableState>(find.byType(Scrollable)).position;
      position().jumpTo(position().maxScrollExtent);
      await tester.pump();
      final anchor = find.byKey(const ValueKey('row-066'));
      final prependBefore = tester.getTopLeft(anchor).dy;
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();
      expect(c.messages.length, 60);
      expect(tester.getTopLeft(anchor).dy, closeTo(prependBefore, 1));
      final before = tester.getTopLeft(anchor).dy;
      records.add({
        'id': '096',
        'content': 'New',
        'createdAt': '2026-11-09T00:00:00.000Z',
        'isStarred': false,
      });
      await c.refresh();
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(anchor).dy, closeTo(before, 1));
      final saved = position().pixels;
      await c.select(const Conversation(id: 'b', title: 'B'));
      await tester.pumpAndSettle();
      await c.select(const Conversation(id: 'a', title: 'A'));
      await tester.pumpAndSettle();
      expect(position().pixels, closeTo(saved, 1));
      failOlder = true;
      position().jumpTo(position().maxScrollExtent);
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();
      expect(find.text('加载失败，点击重试'), findsOneWidget);
      expect(c.messages.length, 61);
      failOlder = false;
      await tester.tap(find.text('加载失败，点击重试'));
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();
      expect(c.messages.length, 91);
      await tester.tap(find.text('回到底部'));
      await tester.pumpAndSettle();
      expect(position().pixels, closeTo(position().minScrollExtent, 1));
      records.add({
        'id': '097',
        'content': 'New at bottom',
        'createdAt': '2026-11-09T00:00:00.000Z',
        'isStarred': false,
      });
      await c.refresh();
      await tester.pumpAndSettle();
      expect(position().pixels, closeTo(position().minScrollExtent, 1));
      expect(tester.takeException(), isNull);
    });
  }
}
