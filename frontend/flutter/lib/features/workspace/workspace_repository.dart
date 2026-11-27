import '../../core/network/api_client.dart';
import '../../models/conversation.dart';
import '../../models/file_item.dart';
import '../../models/message.dart';

class WorkspaceRepository {
  WorkspaceRepository(this.api);
  final ApiClient api;

  Future<PageResult<Conversation>> conversations({
    String search = '',
    int page = 1,
  }) async => PageResult.fromJson(
    await api.request(
      '/conversations',
      query: {'q': search, 'page': '$page', 'pageSize': '30'},
    ),
    Conversation.fromJson,
  );

  Future<Conversation> create(String title) async => Conversation.fromJson(
    await api.request('/conversations', method: 'POST', body: {'title': title}),
  );

  Future<Conversation> rename(String id, String title) async =>
      Conversation.fromJson(
        await api.request(
          '/conversations/$id',
          method: 'PATCH',
          body: {'title': title},
        ),
      );

  Future<void> remove(String id) async {
    await api.request('/conversations/$id', method: 'DELETE');
  }

  Future<void> markRead(String id) async {
    await api.request('/conversations/$id/read', method: 'PATCH');
  }

  Future<PageResult<Message>> messages(
    String id, {
    String search = '',
    int page = 1,
    String? before,
    String? since,
    bool includeTotal = true,
  }) async => PageResult.fromJson(
    await api.request(
      '/conversations/$id/messages',
      query: {
        'q': search,
        'page': '$page',
        'pageSize': '30',
        'before': ?before,
        'since': ?since,
        if (!includeTotal) 'includeTotal': 'false',
      },
    ),
    Message.fromJson,
  );

  Future<Message> messageDetail(String id) async =>
      Message.fromJson(await api.request('/messages/$id'));

  Future<PageResult<Message>> favorites({
    String search = '',
    int page = 1,
  }) async => PageResult.fromJson(
    await api.request(
      '/messages/starred',
      query: {'q': search, 'page': '$page', 'pageSize': '30'},
    ),
    Message.fromJson,
  );

  Future<PageResult<FileItem>> files({
    String search = '',
    String? category,
    String sort = 'newest',
    int page = 1,
  }) async => PageResult.fromJson(
    await api.request(
      '/messages/files',
      query: {
        'q': search,
        'page': '$page',
        'pageSize': '30',
        'sort': sort,
        'category': ?category,
      },
    ),
    FileItem.fromJson,
  );

  Future<void> deleteFile(FileItem file) async {
    if (file.kind == 'image') {
      await api.removeImage(file.messageId);
    } else {
      await api.removeAttachment(file.messageId, file.id);
    }
  }

  Future<Conversation> detail(String id) async =>
      Conversation.fromJson(await api.request('/conversations/$id'));

  Future<void> pin(Conversation conversation) async {
    await api.request(
      '/conversations/${conversation.id}',
      method: 'PATCH',
      body: {'pinned': !conversation.isPinned},
    );
  }

  Future<void> deleteMessage(Message message) async {
    await api.request('/messages/${message.id}', method: 'DELETE');
    api.mediaCache.invalidateMessage(message.id);
  }

  Future<void> editMessage(Message message, String content) async {
    await api.request(
      '/messages/${message.id}',
      method: 'PATCH',
      body: {'content': content.trim()},
    );
  }

  Future<void> deleteAttachment(Message message, Attachment file) async {
    await api.removeAttachment(message.id, file.id);
  }

  Future<void> deleteImage(Message message) async {
    await api.removeImage(message.id);
  }

  Future<void> send(String id, String content, {String? clientId}) async {
    await api.request(
      '/conversations/$id/messages',
      method: 'POST',
      body: {'content': content, 'clientId': ?clientId},
    );
  }

  Future<void> annotate(Message message, String text) async {
    await api.request(
      '/messages/${message.id}',
      method: 'PATCH',
      body: {'annotation': text.trim()},
    );
  }

  Future<void> star(Message message) async {
    await api.request(
      '/messages/${message.id}',
      method: 'PATCH',
      body: {'isStarred': !message.starred},
    );
  }
}
