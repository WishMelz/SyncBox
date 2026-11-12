import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_selector/file_selector.dart';

import '../../../core/network/api_client.dart';
import '../../../models/message.dart';
import 'message_card.dart';
import '../../../shared/widgets/highlight_text.dart';
import '../../../shared/message_presentation.dart';

class AttachmentTile extends StatefulWidget {
  const AttachmentTile({
    super.key,
    required this.api,
    required this.message,
    required this.file,
    this.query = '',
    this.onContentSizeChanged,
  });
  final ApiClient api;
  final Message message;
  final Attachment file;
  final String query;
  final VoidCallback? onContentSizeChanged;
  @override
  State<AttachmentTile> createState() => _AttachmentTileState();
}

class _AttachmentTileState extends State<AttachmentTile> {
  bool saving = false;
  Future<void> save() async {
    setState(() => saving = true);
    try {
      final data = await widget.api.attachmentBytes(
        widget.message.id,
        widget.file.id,
      );
      bool saved = false;
      if (Platform.isAndroid) {
        saved =
            await const MethodChannel('syncbox/files').invokeMethod<bool>(
              'save',
              {'name': widget.file.name, 'bytes': data},
            ) ??
            false;
      } else {
        final location = await getSaveLocation(suggestedName: widget.file.name);
        if (location != null) {
          await XFile.fromData(data).saveTo(location.path);
          saved = true;
        }
      }
      if (mounted && saved) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('文件已保存')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('文件保存失败，请重试。')),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (widget.file.hasPreview && !widget.file.deleted)
        PrivateMessageImage(
          key: ValueKey('${widget.file.id}-preview'),
          load: () => widget.api.attachmentBytes(
            widget.message.id,
            widget.file.id,
            preview: true,
          ),
          onContentSizeChanged: widget.onContentSizeChanged,
        ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.insert_drive_file_outlined),
        title: HighlightText(
          widget.file.name,
          query: widget.query,
          maxLines: highlightRanges(widget.file.name, widget.query).isEmpty
              ? 2
              : null,
          overflow: highlightRanges(widget.file.name, widget.query).isEmpty
              ? TextOverflow.ellipsis
              : TextOverflow.visible,
        ),
        subtitle: Text(
          widget.file.deleted
              ? '文件已清理'
              : '${(widget.file.size / 1024).toStringAsFixed(1)} KB',
        ),
        trailing: IconButton(
          tooltip: saving ? '保存中…' : '保存文件',
          onPressed: widget.file.deleted || saving ? null : save,
          icon: saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.download_outlined),
        ),
      ),
    ],
  );
}
