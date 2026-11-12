import 'dart:async';

import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';

import '../workspace_controller.dart';
import 'message_history_feed.dart';
import 'message_card.dart';
import 'annotation_dialog.dart';
import 'favorites_view.dart';

import 'package:flutter/services.dart';

import 'dart:io';

import '../../../shared/message_presentation.dart';

class ConversationDetail extends StatefulWidget {
  const ConversationDetail({
    super.key,
    required this.controller,
    required this.onRename,
    required this.onDelete,
    required this.compact,
  });
  final WorkspaceController controller;
  final VoidCallback onRename, onDelete;
  final bool compact;
  @override
  State<ConversationDetail> createState() => _ConversationDetailState();
}

class _ConversationDetailState extends State<ConversationDetail> {
  late final TextEditingController _text;
  late final TextEditingController _search;
  late final FocusNode _searchFocus;
  Timer? _searchTimer;
  bool _searchOpen = false;
  @override
  void initState() {
    super.initState();
    _text = TextEditingController(
      text: widget.controller.drafts[widget.controller.selected!.id] ?? '',
    );
    _search = TextEditingController(text: widget.controller.messageSearch);
    _searchFocus = FocusNode();
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _text.dispose();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> submitSearch([String? value]) async {
    _searchTimer?.cancel();
    final query = (value ?? _search.text).trim();
    _search.text = query;
    await widget.controller.searchMessages(query);
  }

  void toggleSearch() {
    setState(() => _searchOpen = !_searchOpen);
    if (_searchOpen) {
      _searchFocus.requestFocus();
    } else {
      _searchTimer?.cancel();
      _search.clear();
      if (widget.controller.messageSearch.isNotEmpty) {
        widget.controller.searchMessages('');
      }
    }
  }

  void focusSearch() {
    if (!_searchOpen) setState(() => _searchOpen = true);
    _searchFocus.requestFocus();
  }

  Future<void> send() async {
    final c = widget.controller;
    final id = c.selected!.id;
    await c.send(_text.text);
    // A failed refresh after successful delivery must not leave a duplicate draft.
    if (mounted && !c.drafts.containsKey(id)) {
      _text.clear();
      _searchTimer?.cancel();
      if (c.messageSearch.isEmpty) _search.clear();
    }
  }

  Future<void> chooseFiles() async {
    final c = widget.controller;
    final id = c.selected!.id;
    try {
      final picked = await openFiles();
      if (picked.isEmpty || !mounted) return;
      final files = [...?c.fileDrafts[id], ...picked];
      var size = 0;
      for (final file in files) {
        final length = await file.length();
        if (length == 0) throw const FormatException('不能发送空文件');
        size += length;
      }
      if (files.length > 5 || size > 20 * 1024 * 1024) {
        throw const FormatException('最多 5 个附件，合计不超过 20 MB');
      }
      if (mounted) c.attachFiles(id, files);
    } on FormatException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法添加附件，请重试。')),
        );
      }
    }
  }

  Future<void> chooseImage() async {
    final c = widget.controller;
    final id = c.selected!.id;
    try {
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(
            label: '图片',
            extensions: ['jpg', 'jpeg', 'png', 'webp', 'gif'],
            mimeTypes: ['image/jpeg', 'image/png', 'image/webp', 'image/gif'],
          ),
        ],
      );
      if (file == null || !mounted) return;
      if (await file.length() > 8 * 1024 * 1024) {
        throw const FormatException('图片不能超过 8 MB');
      }
      final bytes = await file.readAsBytes();
      if (mounted) c.attachImage(id, bytes);
    } on FormatException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法添加图片，请重试。')),
        );
      }
    }
  }

  Widget _messageRow(
    BuildContext context,
    int index, {
    VoidCallback? onContentSizeChanged,
  }) {
    final c = widget.controller;
    final message = c.messages[index];
    final older = index + 1 < c.messages.length
        ? c.messages[index + 1].createdAt
        : null;
    final dayStart = older == null || !sameMessageDay(message.createdAt, older);
    return Column(
      children: [
        if (dayStart)
          Padding(
            // Keep the separator light and compact, matching the Telegram-style
            // date pill used by the web client. The default Material Chip adds
            // a larger height, avatar spacing, and a theme-dependent shadow.
            padding: const EdgeInsets.only(top: 10, bottom: 7),
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: Color(0x30768F9E),
                borderRadius: BorderRadius.all(Radius.circular(12)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 4,
                ),
                child: Text(
                  messageDayLabel(message.createdAt),
                  style: const TextStyle(
                    color: Color(0xff5b7383),
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ),
        MessageCard(
          key: ValueKey(message.id),
          message: message,
          query: c.messageSearch,
          showDate: false,
          api: c.repository.api,
          own:
              message.deviceId != null && message.deviceId == c.currentDeviceId,
          onDelete: c.busy
              ? null
              : () => confirmDeleteMessage(context, c, message),
          loadImage: () => c.repository.api.imageBytes(message.id),
          onAnnotate: c.busy
              ? null
              : () => showDialog<void>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => AnnotationDialog(
                    message: message,
                    onSave: (text) => c.annotate(message, text),
                  ),
                ),
          onStar: c.busy ? null : () => c.star(message),
          onContentSizeChanged: onContentSizeChanged,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final shortViewport =
        MediaQuery.sizeOf(context).height -
            MediaQuery.viewInsetsOf(context).bottom <
        500;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            focusSearch,
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): focusSearch,
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_searchOpen) toggleSearch();
        },
      },
      child: Focus(
        autofocus: true,
        skipTraversal: true,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              child: Row(
                children: [
                  if (widget.compact)
                    IconButton(
                      tooltip: '返回会话列表',
                      onPressed: () => c.select(null),
                      icon: const Icon(Icons.arrow_back),
                    ),
                  Expanded(
                    child: Text(
                      c.selected!.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: _searchOpen ? '收起搜索' : '搜索消息',
                    onPressed: toggleSearch,
                    icon: Icon(_searchOpen ? Icons.close : Icons.search),
                  ),
                  IconButton(
                    tooltip: '重命名会话',
                    onPressed: c.busy ? null : widget.onRename,
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  PopupMenuButton<String>(
                    tooltip: '会话操作',
                    enabled: !c.busy,
                    onSelected: (action) {
                      if (action == 'pin') {
                        c.pin(
                          c.conversations
                                  .where((v) => v.id == c.selected!.id)
                                  .firstOrNull ??
                              c.selected!,
                        );
                      }
                      if (action == 'delete') widget.onDelete();
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'pin',
                        child: Text(
                          (c.conversations
                                          .where((v) => v.id == c.selected!.id)
                                          .firstOrNull ??
                                      c.selected!)
                                  .isPinned
                              ? '取消置顶'
                              : '置顶',
                        ),
                      ),
                      const PopupMenuItem(value: 'delete', child: Text('删除会话')),
                    ],
                  ),
                ],
              ),
            ),
            if (_searchOpen)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  controller: _search,
                  focusNode: _searchFocus,
                  decoration: InputDecoration(
                    hintText: '搜索消息、批注或文件名',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: '清空搜索',
                            onPressed: () {
                              _search.clear();
                              setState(() {});
                              submitSearch('');
                            },
                            icon: const Icon(Icons.clear),
                          ),
                  ),
                  textInputAction: TextInputAction.search,
                  onChanged: (value) {
                    setState(() {});
                    _searchTimer?.cancel();
                    _searchTimer = Timer(const Duration(milliseconds: 350), () {
                      if (mounted) widget.controller.searchMessages(value);
                    });
                  },
                  onEditingComplete: () {},
                  onSubmitted: submitSearch,
                ),
              ),
            Expanded(
              child: c.messages.isEmpty
                  ? Center(
                      child: Text(
                        c.refreshing
                            ? '正在加载消息…'
                            : c.messageSearch.isEmpty
                            ? '发送内容，在其他设备继续'
                            : '没有匹配的消息',
                      ),
                    )
                  : MessageHistoryFeed(
                      key: ValueKey(c.historyKey),
                      controller: c,
                      itemBuilder: (context, index) =>
                          _messageRow(context, index),
                      itemBuilderWithSize: (context, index, onSizeChanged) =>
                          _messageRow(
                            context,
                            index,
                            onContentSizeChanged: onSizeChanged,
                          ),
                    ),
            ),
            if ((c.fileDrafts[c.selected!.id] ?? []).isNotEmpty)
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: shortViewport ? 64 : 130,
                ),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final file in c.fileDrafts[c.selected!.id]!)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.attach_file, size: 18),
                        title: Text(
                          file.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: IconButton(
                          tooltip: '移除附件',
                          onPressed: c.busy
                              ? null
                              : () => c.attachFiles(
                                  c.selected!.id,
                                  c.fileDrafts[c.selected!.id]!
                                      .where((v) => v != file)
                                      .toList(),
                                ),
                          icon: const Icon(Icons.close, size: 18),
                        ),
                      ),
                  ],
                ),
              ),
            if (c.imageDrafts[c.selected!.id] != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Image.memory(
                      c.imageDrafts[c.selected!.id]!,
                      width: 80,
                      height: 64,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const Icon(Icons.broken_image),
                    ),
                    const SizedBox(width: 10),
                    const Text('图片待发送'),
                    const Spacer(),
                    IconButton(
                      tooltip: '移除图片',
                      onPressed: c.busy
                          ? null
                          : () => c.attachImage(c.selected!.id, null),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    PopupMenuButton<String>(
                      tooltip: '添加图片或文件',
                      enabled: !c.busy,
                      onSelected: (value) {
                        if (value == 'image') chooseImage();
                        if (value == 'file') chooseFiles();
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'image',
                          enabled:
                              c.fileDrafts[c.selected!.id]?.isEmpty ?? true,
                          child: const ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.photo_outlined),
                            title: Text('选择图片'),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'file',
                          enabled: c.imageDrafts[c.selected!.id] == null,
                          child: const ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.attach_file),
                            title: Text('选择文件'),
                          ),
                        ),
                        const PopupMenuItem<String>(
                          enabled: false,
                          child: Text('最多 5 个附件，合计不超过 20 MB'),
                        ),
                      ],
                      icon: const Icon(Icons.attach_file),
                    ),
                    Expanded(
                      child: Focus(
                        onKeyEvent: (node, event) {
                          if (event is KeyDownEvent &&
                              event.logicalKey == LogicalKeyboardKey.enter &&
                              (HardwareKeyboard.instance.isControlPressed ||
                                  (Platform.isWindows &&
                                      !HardwareKeyboard
                                          .instance
                                          .isShiftPressed &&
                                      !HardwareKeyboard
                                          .instance
                                          .isAltPressed)) &&
                              _text.value.composing.isCollapsed) {
                            if (!c.busy) send();
                            return KeyEventResult.handled;
                          }
                          return KeyEventResult.ignored;
                        },
                        child: TextField(
                          controller: _text,
                          enabled: !c.busy,
                          minLines: 1,
                          maxLines: shortViewport ? 2 : 5,
                          maxLength: 50000,
                          onChanged: (value) =>
                              c.drafts[c.selected!.id] = value,
                          decoration: const InputDecoration(
                            hintText: '发送文案或链接…',
                            counterText: '',
                            filled: true,
                            fillColor: Colors.white,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      tooltip: '发送消息',
                      onPressed: c.busy ? null : send,
                      icon: const Icon(Icons.send),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
