class Conversation {
  const Conversation({
    required this.id,
    required this.title,
    this.preview = '',
    this.count = 0,
    this.isPinned = false,
    this.unreadCount = 0,
  });
  final String id, title, preview;
  final int count;
  final bool isPinned;
  final int unreadCount;
  Conversation withUnreadCount(int value) => Conversation(
    id: id,
    title: title,
    preview: preview,
    count: count,
    isPinned: isPinned,
    unreadCount: value,
  );
  factory Conversation.fromJson(Map<String, dynamic> json) => Conversation(
    id: json['id'] as String,
    isPinned: json['isPinned'] == true,
    title: json['title'] as String,
    preview: json['preview'] as String? ?? '',
    count: json['messageCount'] as int? ?? 0,
    unreadCount: json['unreadCount'] as int? ?? 0,
  );
}

class PageResult<T> {
  const PageResult(
    this.items,
    this.page,
    this.totalPages, {
    this.total,
    this.hasMore,
    this.nextCursor,
  });
  final List<T> items;
  final int page, totalPages;
  final int? total;
  final bool? hasMore;
  final String? nextCursor;
  factory PageResult.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) parse,
  ) => PageResult(
    (json['items'] as List)
        .map((v) => parse(v as Map<String, dynamic>))
        .toList(),
    json['page'] as int,
    json['totalPages'] as int,
    total: json['total'] as int?,
    hasMore: json['hasMore'] as bool?,
    nextCursor: json['nextCursor'] as String?,
  );
}
