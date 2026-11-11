import '../../models/conversation.dart';
import '../../models/message.dart';

/// A bounded, in-memory reading window. No queued sends or persistent copies.
class MessageHistory {
  MessageHistory(this.fetch);
  final Future<PageResult<Message>> Function({String? before, String? since})
  fetch;
  List<Message> items = [];
  int totalPages = 0;
  bool ready = false, hasOlder = false, loadingOlder = false;
  Object? olderError;
  double scrollOffset = 0;
  String? pivotId;
  bool atBottom = true;
  Future<void> _tail = Future.value();
  static String cursor(Message m) =>
      '${m.createdAt.toUtc().toIso8601String()}|${m.id}';
  static List<Message> merge(List<Message> first, List<Message> second) {
    final unique = {
      for (final m in [...first, ...second]) m.id: m,
    };
    return unique.values.toList()..sort((a, b) {
      final date = b.createdAt.compareTo(a.createdAt);
      return date == 0 ? b.id.compareTo(a.id) : date;
    });
  }

  Future<void> _enqueue(Future<void> Function() work) {
    final task = _tail.then((_) => work());
    _tail = task.then((_) {}, onError: (Object _) {});
    return task;
  }

  Future<void> refresh() => _enqueue(() async {
    final since = items.isEmpty ? null : cursor(items.last);
    var page = await fetch(since: since);
    var result = page.items;
    final seen = <String>{};
    while (since != null && page.hasMore == true && page.nextCursor != null) {
      if (!seen.add(page.nextCursor!)) throw StateError('历史消息加载位置未前进');
      page = await fetch(since: since, before: page.nextCursor);
      result = merge(result, page.items);
    }
    if (result.isEmpty && (page.total ?? 0) > 0 && since != null) {
      page = await fetch();
      result = page.items;
    }
    items = merge([], result);
    totalPages = page.totalPages;
    hasOlder = page.total != null ? page.total! > items.length : totalPages > 1;
    ready = true;
  });
  Future<void> loadOlder() async {
    if (!ready || !hasOlder || loadingOlder) return;
    loadingOlder = true;
    olderError = null;
    try {
      await _enqueue(() async {
        if (items.isEmpty) return;
        final page = await fetch(before: cursor(items.last));
        items = merge(items, page.items);
        totalPages = page.totalPages;
        hasOlder =
            page.hasMore ?? ((page.total ?? items.length) > items.length);
      });
    } catch (e) {
      olderError = e;
      rethrow;
    } finally {
      loadingOlder = false;
    }
  }
}
