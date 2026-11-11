import 'package:flutter/material.dart';

import '../workspace_controller.dart';
import '../../../models/conversation.dart';
import '../../../shared/widgets/page_controls.dart';
import '../../../shared/widgets/highlight_text.dart';

class ConversationList extends StatelessWidget {
  const ConversationList({
    super.key,
    required this.controller,
    required this.onCreate,
    this.onRename,
    this.onDelete,
    this.showHeader = true,
  });
  final WorkspaceController controller;
  final VoidCallback onCreate;
  final void Function(Conversation)? onRename, onDelete;
  final bool showHeader;

  List<PopupMenuEntry<String>> menu(Conversation c) => [
    PopupMenuItem(value: 'pin', child: Text(c.isPinned ? '取消置顶' : '置顶')),
    const PopupMenuItem(value: 'rename', child: Text('重命名')),
    const PopupMenuItem(value: 'delete', child: Text('删除会话')),
  ];

  void action(Conversation c, String? value) {
    if (controller.busy) return;
    if (value == 'pin') controller.pin(c);
    if (value == 'rename') onRename?.call(c);
    if (value == 'delete') onDelete?.call(c);
  }

  Future<void> openMenu(
    BuildContext context,
    Conversation c,
    Offset point,
  ) async {
    if (controller.busy) return;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final position = overlay.globalToLocal(point);
    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        overlay.size.width - position.dx,
        overlay.size.height - position.dy,
      ),
      items: menu(c),
    );
    if (context.mounted) action(c, value);
  }

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    child: Column(
      children: [
        if (showHeader)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Text('消息列表', style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                IconButton(
                  tooltip: '新建会话',
                  onPressed: controller.busy ? null : onCreate,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(16, showHeader ? 0 : 8, 16, 8),
          child: TextFormField(
            key: ValueKey(controller.conversationSearch),
            initialValue: controller.conversationSearch,
            decoration: const InputDecoration(
              hintText: '搜索会话和内容',
              prefixIcon: Icon(Icons.search),
              isDense: true,
              filled: true,
              fillColor: Color(0xfff1f4f7),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(14)),
                borderSide: BorderSide.none,
              ),
            ),
            textInputAction: TextInputAction.search,
            onFieldSubmitted: controller.searchConversations,
          ),
        ),
        ListTile(
          dense: true,
          leading: const Icon(Icons.star_outline),
          title: const Text('收藏'),
          selected: controller.favoritesMode,
          onTap: controller.showFavorites,
        ),
        const SizedBox(height: 8),
        Expanded(
          child: controller.conversations.isEmpty
              ? Center(
                  child: Text(
                    controller.conversationSearch.isEmpty
                        ? '暂无会话，点击 + 开始'
                        : '没有匹配的会话',
                  ),
                )
              : ListView.builder(
                  itemCount: controller.conversations.length,
                  itemBuilder: (context, index) {
                    final c = controller.conversations[index];
                    final selected = controller.selected?.id == c.id;
                    return GestureDetector(
                      onSecondaryTapDown: (event) =>
                          openMenu(context, c, event.globalPosition),
                      onLongPressStart: (event) =>
                          openMenu(context, c, event.globalPosition),
                      child: ListTile(
                        selected: selected,
                        selectedTileColor: const Color(0xffe0eff8),
                        selectedColor: const Color(0xff1678ae),
                        leading: Icon(
                          c.isPinned
                              ? Icons.push_pin
                              : Icons.chat_bubble_outline,
                          size: 18,
                        ),
                        trailing: PopupMenuButton<String>(
                          tooltip: '会话操作',
                          icon: Icon(
                            Icons.more_horiz,
                            size: 20,
                            color: selected
                                ? const Color(0xff12628e)
                                : const Color(0xff617785),
                          ),
                          enabled: !controller.busy,
                          onSelected: (value) => action(c, value),
                          itemBuilder: (_) => menu(c),
                        ),
                        title: HighlightText(
                          c.title,
                          query: controller.conversationSearch,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: HighlightText(
                          c.preview.isEmpty ? '发送第一条消息' : c.preview,
                          query: controller.conversationSearch,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => controller.select(c),
                      ),
                    );
                  },
                ),
        ),
        PageControls(
          page: controller.conversationPage,
          pages: controller.conversationPages,
          enabled: !controller.refreshing,
          onChanged: controller.pageConversations,
        ),
      ],
    ),
  );
}
