import 'package:flutter/material.dart';

import '../workspace_controller.dart';
import '../message_history.dart';

/// Keep a stable center message: older rows grow upward and live rows grow
/// downward without changing the reading position of the existing content.
class MessageHistoryFeed extends StatefulWidget {
  const MessageHistoryFeed({
    super.key,
    required this.controller,
    required this.itemBuilder,
    this.onContentSizeChanged,
    this.itemBuilderWithSize,
  });
  final WorkspaceController controller;
  final Widget Function(BuildContext, int) itemBuilder;
  final VoidCallback? onContentSizeChanged;
  final Widget Function(BuildContext, int, VoidCallback)? itemBuilderWithSize;
  @override
  State<MessageHistoryFeed> createState() => _MessageHistoryFeedState();
}

class _MessageHistoryFeedState extends State<MessageHistoryFeed> {
  static const _center = ValueKey('history-center');
  late final MessageHistory _memory;
  late final ScrollController _scroll;
  String? _newest;
  late int _scrollRequest;
  bool _scheduled = false;
  bool _followRequested = false;
  @override
  void initState() {
    super.initState();
    _memory = widget.controller.messageHistory;
    _scrollRequest = widget.controller.scrollToLatest;
    _newest = widget.controller.messages.firstOrNull?.id;
    _scroll = ScrollController(initialScrollOffset: _memory.scrollOffset)
      ..addListener(_onScroll);
    _schedule();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    _memory.scrollOffset = _scroll.offset;
    final bottom = _scroll.offset - _scroll.position.minScrollExtent < 64;
    if (bottom != _memory.atBottom) setState(() => _memory.atBottom = bottom);
    _loadIfNearTop();
  }

  void _loadIfNearTop() {
    if (!_scroll.hasClients ||
        !_memory.hasOlder ||
        _memory.loadingOlder ||
        _memory.olderError != null) {
      return;
    }
    if (_scroll.position.maxScrollExtent - _scroll.offset < 120) {
      widget.controller.loadOlderMessages();
    }
  }

  void _onContentSizeChanged() {
    if (_memory.atBottom) _schedule(follow: true);
    widget.onContentSizeChanged?.call();
  }

  void _schedule({bool follow = false}) {
    _followRequested = _followRequested || follow;
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted || !_scroll.hasClients) return;
      if (_followRequested) _scroll.jumpTo(_scroll.position.minScrollExtent);
      _followRequested = false;
      _loadIfNearTop();
    });
  }

  @override
  void didUpdateWidget(covariant MessageHistoryFeed oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newest = widget.controller.messages.firstOrNull?.id;
    final request = widget.controller.scrollToLatest;
    _schedule(
      follow:
          request != _scrollRequest || (newest != _newest && _memory.atBottom),
    );
    _newest = newest;
    _scrollRequest = request;
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final messages = widget.controller.messages;
    if (!messages.any((m) => m.id == _memory.pivotId)) {
      _memory.pivotId = messages.firstOrNull?.id;
    }
    final pivot = messages.indexWhere((m) => m.id == _memory.pivotId);
    final split = pivot < 0 ? 0 : pivot;
    final newestIndexes = List.generate(split, (n) => split - n - 1);
    Widget row(int index) => KeyedSubtree(
      key: ValueKey(messages[index].id),
      child:
          widget.itemBuilderWithSize?.call(
            context,
            index,
            _onContentSizeChanged,
          ) ??
          widget.itemBuilder(context, index),
    );
    return Stack(
      children: [
        CustomScrollView(
          key: const ValueKey('message-history-scroll'),
          controller: _scroll,
          reverse: true,
          center: _center,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, n) => row(newestIndexes[n]),
                  childCount: split,
                  findChildIndexCallback: (key) {
                    final n = newestIndexes.indexWhere(
                      (i) => ValueKey(messages[i].id) == key,
                    );
                    return n < 0 ? null : n;
                  },
                ),
              ),
            ),
            SliverPadding(
              key: _center,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, n) => row(n + split),
                  childCount: messages.length - split,
                  findChildIndexCallback: (key) {
                    final n =
                        messages.indexWhere((m) => ValueKey(m.id) == key) -
                        split;
                    return n < 0 ? null : n;
                  },
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 40,
                child: Center(
                  child: _memory.loadingOlder
                      ? const Text('正在加载更早消息…')
                      : _memory.olderError != null
                      ? TextButton(
                          onPressed: widget.controller.loadOlderMessages,
                          child: const Text('加载失败，点击重试'),
                        )
                      : Text(
                          _memory.hasOlder ? '向上滚动查看更早消息' : '已到最早消息',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                ),
              ),
            ),
          ],
        ),
        if (!_memory.atBottom)
          Positioned(
            right: 12,
            bottom: 12,
            child: FilledButton.tonalIcon(
              onPressed: () => _scroll.jumpTo(_scroll.position.minScrollExtent),
              icon: const Icon(Icons.arrow_downward, size: 16),
              label: const Text('回到底部'),
            ),
          ),
      ],
    );
  }
}
