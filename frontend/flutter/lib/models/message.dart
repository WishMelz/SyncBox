class Message {
  const Message({
    required this.id,
    required this.content,
    required this.createdAt,
    required this.device,
    required this.starred,
    this.hasImage = false,
    this.annotation = '',
    this.isRead,
    this.deviceId,
    this.conversationId,
    this.conversationTitle,
    this.filesExpired = false,
    this.attachments = const [],
  });
  final String id, content, device, annotation;
  final String? deviceId, conversationId, conversationTitle;
  final bool filesExpired;
  final List<Attachment> attachments;
  final DateTime createdAt;
  final bool starred;
  final bool? isRead;
  final bool hasImage;
  factory Message.fromJson(Map<String, dynamic> json) => Message(
    id: json['id'] as String,
    isRead: json['isRead'] as bool?,
    deviceId: (json['senderDevice'] as Map?)?['id'] as String?,
    conversationId: json['conversationId'] as String?,
    conversationTitle: json['conversationTitle'] as String?,
    filesExpired: json['filesExpired'] == true,
    attachments: (json['attachments'] as List? ?? [])
        .map((v) => Attachment.fromJson(v))
        .toList(),
    content: json['content'] as String,
    annotation: json['annotation'] as String? ?? '',
    createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
    device: (json['senderDevice'] as Map?)?['name'] as String? ?? '未登记设备',
    starred: json['isStarred'] as bool,
    hasImage: json['image'] != null,
  );
}

class Attachment {
  const Attachment({
    required this.id,
    required this.name,
    required this.size,
    this.hasPreview = false,
    this.deleted = false,
  });
  final String id, name;
  final int size;
  final bool hasPreview, deleted;
  factory Attachment.fromJson(Map<String, dynamic> json) => Attachment(
    id: json['id'],
    name: json['name'],
    size: json['size'],
    hasPreview: json['hasPreview'] == true,
    deleted: json['deletedAt'] != null,
  );
}
