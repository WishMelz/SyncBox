import 'message.dart';

class FileItem {
  const FileItem({
    required this.id,
    required this.messageId,
    required this.kind,
    required this.category,
    required this.name,
    required this.mimeType,
    required this.size,
    required this.hasPreview,
    required this.conversationId,
    required this.conversationTitle,
    required this.createdAt,
    this.width,
    this.height,
  });

  final String id;
  final String messageId;
  final String kind;
  final String category;
  final String name;
  final String mimeType;
  final int size;
  final bool hasPreview;
  final int? width;
  final int? height;
  final String conversationId;
  final String conversationTitle;
  final DateTime createdAt;

  Attachment asAttachment() =>
      Attachment(id: id, name: name, size: size, hasPreview: hasPreview);

  Message asMessageShell() => Message(
    id: messageId,
    content: '',
    createdAt: createdAt,
    device: '',
    starred: false,
    hasImage: kind == 'image',
    conversationId: conversationId,
    conversationTitle: conversationTitle,
    attachments: kind == 'attachment' ? [asAttachment()] : const [],
  );

  factory FileItem.fromJson(Map<String, dynamic> json) {
    final kind = json['kind'] as String? ?? 'attachment';
    final category =
        json['category'] as String? ?? (kind == 'image' ? 'image' : 'file');
    return FileItem(
      id: json['id'] as String,
      messageId: json['messageId'] as String,
      kind: kind,
      category: category,
      name: json['name'] as String? ?? '文件',
      mimeType: json['mimeType'] as String? ?? 'application/octet-stream',
      size: json['size'] as int? ?? 0,
      hasPreview: json['hasPreview'] == true,
      width: json['width'] as int?,
      height: json['height'] as int?,
      conversationId: json['conversationId'] as String,
      conversationTitle: json['conversationTitle'] as String? ?? '',
      createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
    );
  }
}
