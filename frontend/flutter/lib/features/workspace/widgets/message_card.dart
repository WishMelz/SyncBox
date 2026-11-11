import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/message.dart';
import '../../../core/network/api_client.dart';
import 'attachment_tile.dart';
import '../../../shared/widgets/highlight_text.dart';
import '../../../shared/message_presentation.dart';

class MessageCard extends StatefulWidget {
  const MessageCard({
    super.key,
    required this.message,
    required this.onStar,
    this.onAnnotate,
    this.loadImage,
    this.onDelete,
    this.onOpen,
    this.api,
    this.own = false,
    this.query = '',
    this.showDate = false,
    this.onContentSizeChanged,
  });
  final Message message;
  final bool own, showDate;
  final String query;
  final ApiClient? api;
  final VoidCallback? onDelete, onOpen, onStar, onAnnotate;
  final Future<Uint8List> Function()? loadImage;
  final VoidCallback? onContentSizeChanged;
  @override
  State<MessageCard> createState() => _MessageCardState();
}

class _MessageCardState extends State<MessageCard> {
  bool hovered = false, menuOpen = false;
  bool copiedNotice = false;
  Timer? _copiedTimer;

  @override
  void dispose() {
    _copiedTimer?.cancel();
    super.dispose();
  }

  List<PopupMenuEntry<String>> get entries => [
    const PopupMenuItem(value: 'copy', child: Text('复制内容')),
    PopupMenuItem(
      value: 'star',
      enabled: widget.onStar != null,
      child: Text(widget.message.starred ? '取消收藏' : '收藏'),
    ),
    PopupMenuItem(
      value: 'annotate',
      enabled: widget.onAnnotate != null,
      child: Text(widget.message.annotation.isEmpty ? '添加批注' : '编辑批注'),
    ),
    PopupMenuItem(
      value: 'delete',
      enabled: widget.onDelete != null,
      child: const Text('删除消息', style: TextStyle(color: Colors.red)),
    ),
  ];
  Future<void> select(String? action) async {
    if (action == 'copy') {
      try {
        await Clipboard.setData(ClipboardData(text: widget.message.content));
        if (mounted) {
          _copiedTimer?.cancel();
          setState(() => copiedNotice = true);
          _copiedTimer = Timer(const Duration(seconds: 2), () {
            if (mounted) setState(() => copiedNotice = false);
          });
        }
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('复制失败，请稍后重试。')));
        }
      }
    }
    if (action == 'star') widget.onStar?.call();
    if (action == 'annotate') widget.onAnnotate?.call();
    if (action == 'delete') widget.onDelete?.call();
  }

  Future<void> openMenu(Offset position) async {
    if (menuOpen) return;
    setState(() => menuOpen = true);
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final local = overlay.globalToLocal(position);
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        local.dx,
        local.dy,
        overlay.size.width - local.dx,
        overlay.size.height - local.dy,
      ),
      items: entries,
    );
    if (!mounted) return;
    setState(() => menuOpen = false);
    await select(result);
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.message;
    final own = widget.own;
    final pointerDevice = [
      TargetPlatform.windows,
      TargetPlatform.macOS,
      TargetPlatform.linux,
    ].contains(Theme.of(context).platform);
    final more = Opacity(
      opacity: !pointerDevice || hovered || menuOpen ? 1 : 0.16,
      child: PopupMenuButton<String>(
        tooltip: '更多操作',
        icon: const Icon(Icons.more_horiz, size: 18),
        onOpened: () => setState(() => menuOpen = true),
        onCanceled: () => setState(() => menuOpen = false),
        onSelected: (action) {
          setState(() => menuOpen = false);
          select(action);
        },
        itemBuilder: (_) => entries,
      ),
    );
    final hasBody =
        !(m.hasImage && m.content == '[图片]') &&
        !(m.attachments.isNotEmpty &&
            m.content == '[附件] ${m.attachments.map((f) => f.name).join('、')}');
    return MouseRegion(
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: LayoutBuilder(
        builder: (context, box) {
          final maxBubble = (box.maxWidth * (box.maxWidth < 600 ? .86 : .76))
              .clamp(0.0, 640.0);
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              mainAxisAlignment: own
                  ? MainAxisAlignment.end
                  : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (own) more,
                Flexible(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onSecondaryTapDown: (event) =>
                        openMenu(event.globalPosition),
                    onLongPressStart: (event) => openMenu(event.globalPosition),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxBubble),
                      child: Material(
                        color: own ? const Color(0xffdceef9) : Colors.white,
                        elevation: 1,
                        shadowColor: const Color(0x1815364d),
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(12),
                          topRight: const Radius.circular(12),
                          bottomLeft: Radius.circular(own ? 12 : 4),
                          bottomRight: Radius.circular(own ? 4 : 12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 11,
                            vertical: 8,
                          ),
                          child: IntrinsicWidth(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  m.device,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: own
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                    color: own
                                        ? const Color(0xff1678ae)
                                        : const Color(0xff617785),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                if (widget.onOpen != null)
                                  TextButton.icon(
                                    onPressed: widget.onOpen,
                                    icon: const Icon(
                                      Icons.arrow_outward,
                                      size: 14,
                                    ),
                                    label: HighlightText(
                                      m.conversationTitle ?? '查看所属会话',
                                      query: widget.query,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                if (m.filesExpired)
                                  const Text(
                                    '图片已清理',
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                if (widget.api != null)
                                  for (final file in m.attachments)
                                    AttachmentTile(
                                      key: ValueKey(file.id),
                                      api: widget.api!,
                                      message: m,
                                      file: file,
                                      query: widget.query,
                                      onContentSizeChanged:
                                          widget.onContentSizeChanged,
                                    ),
                                if (m.hasImage && widget.loadImage != null)
                                  PrivateMessageImage(
                                    key: ValueKey(m.id),
                                    load: widget.loadImage!,
                                    onContentSizeChanged:
                                        widget.onContentSizeChanged,
                                  ),
                                if (hasBody)
                                  HighlightText(
                                    m.content,
                                    query: widget.query,
                                    links: true,
                                    style: const TextStyle(
                                      height: 1.6,
                                      color: Color(0xff243744),
                                    ),
                                  ),
                                if (m.annotation.isNotEmpty)
                                  AnnotationNote(
                                    text: m.annotation,
                                    query: widget.query,
                                    onEdit: widget.onAnnotate,
                                  ),
                                const SizedBox(height: 3),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      if (m.starred)
                                        const Icon(
                                          Icons.star,
                                          size: 11,
                                          color: Color(0xffa78a4d),
                                        ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${widget.showDate ? '${m.createdAt.month}/${m.createdAt.day} ' : ''}${m.createdAt.hour.toString().padLeft(2, '0')}:${m.createdAt.minute.toString().padLeft(2, '0')}',
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: Color(0xff718b9b),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (copiedNotice)
                                  Semantics(
                                    liveRegion: true,
                                    label: '已复制',
                                    child: Align(
                                      alignment: Alignment.centerRight,
                                      child: Text(
                                        '已复制',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: own
                                              ? const Color(0xff1678ae)
                                              : const Color(0xff617785),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (!own) more,
              ],
            ),
          );
        },
      ),
    );
  }
}

class PrivateMessageImage extends StatefulWidget {
  const PrivateMessageImage({
    super.key,
    required this.load,
    this.onContentSizeChanged,
  });
  final Future<Uint8List> Function() load;
  final VoidCallback? onContentSizeChanged;
  @override
  State<PrivateMessageImage> createState() => _PrivateMessageImageState();
}

class _PrivateMessageImageState extends State<PrivateMessageImage> {
  late Future<Uint8List> _data;
  bool _reported = false;
  @override
  void initState() {
    super.initState();
    _data = widget.load();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    future: _data,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return TextButton(
          onPressed: () => setState(() {
            _data = widget.load();
            _reported = false;
          }),
          child: const Text('图片加载失败，重试'),
        );
      }
      if (!snapshot.hasData) {
        return const Padding(
          padding: EdgeInsets.all(20),
          child: CircularProgressIndicator(),
        );
      }
      if (!_reported) {
        _reported = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onContentSizeChanged?.call();
        });
      }
      return InkWell(
        onTap: () => showDialog<void>(
          context: context,
          builder: (context) => Dialog(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.topRight,
                  child: IconButton(
                    tooltip: '关闭图片',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ),
                Flexible(
                  child: InteractiveViewer(
                    child: Image.memory(snapshot.data!, fit: BoxFit.contain),
                  ),
                ),
              ],
            ),
          ),
        ),
        child: Image.memory(
          snapshot.data!,
          height: 240,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => const Text('图片无法显示'),
        ),
      );
    },
  );
}

class AnnotationNote extends StatefulWidget {
  const AnnotationNote({
    super.key,
    required this.text,
    this.query = '',
    this.onEdit,
  });
  final String text;
  final String query;
  final VoidCallback? onEdit;
  @override
  State<AnnotationNote> createState() => _AnnotationNoteState();
}

class _AnnotationNoteState extends State<AnnotationNote> {
  bool expanded = false;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(top: 10),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: const BoxDecoration(
      color: Color(0x10667f94),
      border: Border(left: BorderSide(color: Color(0xff91a9b8), width: 2)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: widget.onEdit,
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Text(
              '批注',
              style: TextStyle(fontSize: 11, color: Color(0xff617785)),
            ),
          ),
        ),
        HighlightText(
          widget.text,
          query: widget.query,
          maxLines:
              expanded ||
                  highlightRanges(widget.text, widget.query).isNotEmpty ||
                  (widget.text.length <= 140 &&
                      widget.text.split('\n').length <= 4)
              ? null
              : 4,
          overflow:
              expanded || highlightRanges(widget.text, widget.query).isNotEmpty
              ? TextOverflow.visible
              : TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, height: 1.6),
        ),
        if (highlightRanges(widget.text, widget.query).isEmpty &&
            (widget.text.length > 140 || widget.text.split('\n').length > 4))
          TextButton(
            onPressed: () => setState(() => expanded = !expanded),
            child: Text(expanded ? '收起' : '展开批注'),
          ),
      ],
    ),
  );
}
