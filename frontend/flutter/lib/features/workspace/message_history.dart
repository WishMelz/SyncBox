import '../../models/conversation.dart';
import '../../models/message.dart';

/// A bounded, in-memory reading window. No queued sends or persistent copies.
class MessageHistory {
  MessageHistory(this.fetch);
  final Future<PageResult<Message>> Function({
    String? before,
    String? since,
    bool includeTotal,
  })
  fetch;
  List<Message> items = [];
  int total = 0;
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

  Future<void> reconcile() => refresh();

  Future<void> refresh() => _enqueue(() async {
    final since = items.isEmpty ? null : cursor(items.last);
    var page = await fetch(since: since, includeTotal: true);
    var result = page.items;
    final seen = <String>{};
    while (since != null && page.hasMore == true && page.nextCursor != null) {
      if (!seen.add(page.nextCursor!)) throw StateError('历史消息加载位置未前进');
      page = await fetch(
        since: since,
        before: page.nextCursor,
        includeTotal: false,
      );
      result = merge(result, page.items);
    }
    if (result.isEmpty && (page.total ?? 0) > 0 && since != null) {
      page = await fetch(includeTotal: true);
      result = page.items;
    }
    items = merge([], result);
    total = page.total ?? items.length;
    totalPages = page.totalPages > 0 || total == 0
        ? page.totalPages
        : ((total + 29) ~/ 30);
    hasOlder = page.total != null ? page.total! > items.length : totalPages > 1;
    ready = true;
  });

  Future<void> refreshLatest() => _enqueue(() async {
    if (!ready) {
      final page = await fetch(includeTotal: true);
      items = merge([], page.items);
      total = page.total ?? items.length;
      totalPages = page.totalPages > 0 || total == 0
          ? page.totalPages
          : ((total + 29) ~/ 30);
      hasOlder = page.total != null ? page.total! > items.length : totalPages > 1;
      ready = true;
      return;
    }
    final page = await fetch(includeTotal: true);
    if (page.hasMore != true || page.items.isEmpty) {
      items = merge([], page.items);
    } else {
      final boundaryCursor = cursor(page.items.last);
      final olderKept = items
          .where((m) => cursor(m).compareTo(boundaryCursor) < 0)
          .toList();
      items = merge(page.items, olderKept);
    }
    total = page.total ?? items.length;
    totalPages = page.totalPages > 0 || total == 0
        ? page.totalPages
        : ((total + 29) ~/ 30);
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
        final page = await fetch(
          before: cursor(items.last),
          includeTotal: false,
        );
        items = merge(items, page.items);
        if (page.total != null) {
          total = page.total!;
        } else if (total < items.length) {
          total = items.length;
        }
        totalPages = page.totalPages > 0
            ? page.totalPages
            : (total == 0 ? 0 : ((total + 29) ~/ 30));
        hasOlder = page.hasMore ?? (total > items.length);
      });
    } catch (e) {
      olderError = e;
      rethrow;
    } finally {
      loadingOlder = false;
    }
  }

  void upsertMessage(Message message) {
    final existed = items.any((m) => m.id == message.id);
    items = merge(items, [message]);
    if (!existed) {
      total = total + 1 > items.length ? total + 1 : items.length;
    } else if (total < items.length) {
      total = items.length;
    }
    totalPages = total == 0 ? 0 : ((total + 29) ~/ 30);
    hasOlder = total > items.length;
  }

  void removeMessage(String id) {
    final existed = items.any((m) => m.id == id);
    if (!existed) return;
    items = items.where((m) => m.id != id).toList();
    total = (total - 1) < items.length ? items.length : total - 1;
    totalPages = total == 0 ? 0 : ((total + 29) ~/ 30);
    hasOlder = total > items.length;
  }
}
