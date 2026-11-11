import 'package:flutter/material.dart';

import '../../../models/message.dart';
import '../../../core/network/api_client.dart';

class AnnotationDialog extends StatefulWidget {
  const AnnotationDialog({
    super.key,
    required this.message,
    required this.onSave,
  });
  final Message message;
  final Future<void> Function(String) onSave;
  @override
  State<AnnotationDialog> createState() => _AnnotationDialogState();
}

class _AnnotationDialogState extends State<AnnotationDialog> {
  late final TextEditingController text = TextEditingController(
    text: widget.message.annotation,
  );
  bool busy = false, confirmDelete = false;
  String? error;
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  Future<void> save(String value) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.onSave(value.trim());
      if (mounted) {
        setState(() => busy = false);
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e is ApiException ? e.message : '保存失败，请重试';
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: Text(widget.message.annotation.isEmpty ? '添加批注' : '编辑批注'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.message.content,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: text,
                autofocus: true,
                enabled: !busy,
                minLines: 4,
                maxLines: 8,
                maxLength: 2000,
                decoration: const InputDecoration(
                  labelText: '批注',
                  hintText: '补充用途、想法或关键词…',
                  alignLabelWithHint: true,
                ),
                onChanged: (_) => setState(() => confirmDelete = false),
              ),
              const Text('所有设备可见，可通过搜索找到', style: TextStyle(fontSize: 12)),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (confirmDelete)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text('删除这条批注？消息和附件会保留。'),
                ),
            ],
          ),
        ),
      ),
      actions: [
        if (widget.message.annotation.isNotEmpty)
          TextButton(
            onPressed: busy
                ? null
                : () => confirmDelete
                      ? save('')
                      : setState(() => confirmDelete = true),
            child: Text(confirmDelete ? '确认删除批注' : '删除批注'),
          ),
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed:
              busy ||
                  text.text.trim().isEmpty ||
                  text.text.runes.length > 2000 ||
                  text.text.trim() == widget.message.annotation
              ? null
              : () => save(text.text),
          child: Text(busy ? '保存中…' : '保存批注'),
        ),
      ],
    ),
  );
}
