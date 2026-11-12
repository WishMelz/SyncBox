import 'package:flutter/material.dart';

import '../../../models/message.dart';
import '../../../shared/widgets/page_controls.dart';
import '../workspace_controller.dart';
import 'message_card.dart';
import 'annotation_dialog.dart';

Future<void> confirmDeleteMessage(
  BuildContext context,
  WorkspaceController controller,
  Message message,
) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('删除这条消息？'),
      content: const Text('消息和附件会从所有设备永久删除。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('删除'),
        ),
      ],
    ),
  );
  if (result == true && context.mounted) {
    await controller.deleteMessage(message);
  }
}

class FavoritesView extends StatelessWidget {
  const FavoritesView({
    super.key,
    required this.controller,
    required this.compact,
  });
  final WorkspaceController controller;
  final bool compact;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            if (compact)
              IconButton(
                tooltip: '返回会话列表',
                onPressed: () => controller.select(null),
                icon: const Icon(Icons.arrow_back),
              ),
            Text('收藏', style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: TextFormField(
          initialValue: controller.messageSearch,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: '搜索正文、批注或文件名',
          ),
          textInputAction: TextInputAction.search,
          onFieldSubmitted: controller.searchMessages,
        ),
      ),
      Expanded(
        child: controller.messages.isEmpty
            ? Center(
                child: Text(
                  controller.refreshing
                      ? '正在加载收藏…'
                      : controller.messageSearch.isEmpty
                      ? '收藏重要内容，方便下次查找'
                      : '没有匹配的收藏',
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: controller.messages.length,
                itemBuilder: (context, index) {
                  final message = controller.messages[index];
                  return MessageCard(
                    key: ValueKey(message.id),
                    message: message,
                    query: controller.messageSearch,
                    showDate: true,
                    api: controller.repository.api,
                    own:
                        message.deviceId != null &&
                        message.deviceId == controller.currentDeviceId,
                    loadImage: () =>
                        controller.repository.api.imageBytes(message.id),
                    onStar: controller.busy
                        ? null
                        : () => controller.star(message),
                    onOpen: () => controller.openConversation(message),
                    onDelete: controller.busy
                        ? null
                        : () => confirmDeleteMessage(
                            context,
                            controller,
                            message,
                          ),
                    onAnnotate: controller.busy
                        ? null
                        : () => showDialog<void>(
                            context: context,
                            barrierDismissible: false,
                            builder: (_) => AnnotationDialog(
                              message: message,
                              onSave: (text) =>
                                  controller.annotate(message, text),
                            ),
                          ),
                  );
                },
              ),
      ),
      PageControls(
        page: controller.messagePage,
        pages: controller.messagePages,
        enabled: !controller.refreshing,
        onChanged: controller.pageMessages,
      ),
    ],
  );
}
