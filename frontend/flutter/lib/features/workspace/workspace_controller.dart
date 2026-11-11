import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:file_selector/file_selector.dart';

import '../../core/network/api_client.dart';
import '../../core/network/sync_events.dart';
import '../../core/storage/session_store.dart';
import '../../models/conversation.dart';
import '../../models/message.dart';
import 'workspace_repository.dart';
import 'message_history.dart';

class WorkspaceController extends ChangeNotifier {
  WorkspaceController(this.repository, {required this.onExpired});
  final WorkspaceRepository repository;
  final Future<void> Function() onExpired;
  List<Conversation> conversations = [];
  List<Message> messages = [];
  bool favoritesMode = false;
  String? currentDeviceId;
  DateTime? lastSynced;
  final Map<String, List<XFile>> fileDrafts = {};
  final Map<String, _SendAttempt> _sendAttempts = {};
  final Map<String, MessageHistory> _histories = {};
  int scrollToLatest = 0;
  String get historyKey => '${selected?.id ?? ''}:$messageSearch';
  MessageHistory get messageHistory {
    final key = historyKey, id = selected?.id ?? '', query = messageSearch;
    if (!_histories.containsKey(key)) {
      _histories[key] = MessageHistory(
        ({before, since}) => repository.messages(
          id,
          search: query,
          before: before,
          since: since,
        ),
      );
      if (_histories.length > 20) _histories.remove(_histories.keys.first);
    }
    return _histories[key]!;
  }

  Future<void> loadOlderMessages() async {
    if (selected == null || favoritesMode) return;
    final key = historyKey, history = messageHistory;
    final work = history.loadOlder();
    _notify();
    try {
      await work;
    } catch (e) {
      if (e is ApiException && e.status == 401) await _handle(e);
    } finally {
      if (key == historyKey) messages = history.items;
      _notify();
    }
  }

  void attachFiles(String id, List<XFile> files) {
    fileDrafts[id] = files;
    _notify();
  }

  Future<void> showFavorites() async {
    _selectionVersion++;
    favoritesMode = true;
    selected = null;
    messages = [];
    messageSearch = '';
    messagePage = 1;
    messagePages = 0;
    _notify();
    await _refreshAfterCurrent();
  }

  Future<void> openConversation(Message message) async {
    if (message.conversationId == null) return;
    try {
      await select(await repository.detail(message.conversationId!));
    } catch (e) {
      await _handle(e);
    }
  }

  Conversation? selected;
  int conversationPage = 1,
      conversationPages = 0,
      messagePage = 1,
      messagePages = 0;
  String conversationSearch = '', messageSearch = '';
  final Map<String, String> drafts = {};
  final Map<String, Uint8List> imageDrafts = {};
  void attachImage(String id, Uint8List? data) {
    if (data == null) {
      imageDrafts.remove(id);
    } else {
      imageDrafts[id] = data;
    }
    _notify();
  }

  String? error;
  bool busy = false, refreshing = false, _disposed = false;
  int _selectionVersion = 0;
  Timer? _timer, _reconnect, _eventRefresh;
  SyncEventConnection? _eventConnection;
  StreamSubscription<Map<String, dynamic>>? _eventSubscription;
  bool _eventsActive = false, realtimeConnected = false;
  bool _refreshPending = false;
  int _eventGeneration = 0, _retrySeconds = 3;
  void start() => setActive(true);

  void setActive(bool active) {
    if (_disposed || _eventsActive == active) return;
    _eventsActive = active;
    _eventGeneration++;
    _timer?.cancel();
    _reconnect?.cancel();
    _eventRefresh?.cancel();
    unawaited(_eventSubscription?.cancel());
    _eventConnection?.close();
    _eventConnection = null;
    realtimeConnected = false;
    _refreshPending = false;
    if (active) {
      _retrySeconds = 3;
      _setPolling();
      _connectEvents(_eventGeneration);
      unawaited(refresh());
    }
    _notify();
  }

  void _setPolling() {
    _timer?.cancel();
    if (_eventsActive) {
      _timer = Timer.periodic(
        Duration(seconds: realtimeConnected ? 30 : 5),
        (_) => refresh(),
      );
    }
  }

  void _connectEvents(int generation) {
    if (_disposed || !_eventsActive || generation != _eventGeneration) return;
    _eventConnection = repository.api.events();
    _eventSubscription = _eventConnection!.stream.listen(
      (event) {
        if (_disposed || !_eventsActive || generation != _eventGeneration) {
          return;
        }
        if (event['type'] == 'connected') {
          realtimeConnected = true;
          _retrySeconds = 3;
          _setPolling();
          _notify();
          _queueRefresh(); // Catch up changes made while disconnected.
        } else if (event['type'] == 'invalidate') {
          _queueRefresh();
        }
      },
      onError: (Object e) {
        if (_disposed || generation != _eventGeneration) return;
        if (e is ApiException && e.status == 401) {
          unawaited(_handle(e));
        }
      },
      onDone: () {
        if (_disposed || !_eventsActive || generation != _eventGeneration) {
          return;
        }
        realtimeConnected = false;
        _setPolling();
        _notify();
        _reconnect = Timer(
          Duration(seconds: _retrySeconds),
          () => _connectEvents(generation),
        );
        _retrySeconds = (_retrySeconds * 2).clamp(3, 30);
      },
    );
  }

  void _queueRefresh() {
    if (_disposed || !_eventsActive) return;
    _refreshPending = true;
    // Keep a single pending refresh even while a request or mutation is running.
    if (_eventRefresh?.isActive == true) return;
    _eventRefresh = Timer(const Duration(milliseconds: 150), () {
      if (!_disposed && _eventsActive) unawaited(refresh());
    });
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _handle(Object e, {String? message}) async {
    if (_disposed) return;
    if (e is ApiException && e.status == 401) {
      setActive(false);
      await onExpired();
      return;
    }
    error = message ?? (e is ApiException ? e.message : '操作失败，请重试');
    _notify();
  }

  Future<void> refresh({String? failureMessage}) async {
    if (_disposed) return;
    if (refreshing || busy) {
      _refreshPending = true;
      return;
    }
    _refreshPending = false;
    refreshing = true;
    _notify();
    final version = _selectionVersion,
        id = selected?.id,
        search = conversationSearch,
        cp = conversationPage,
        mp = messagePage,
        mq = messageSearch,
        starred = favoritesMode;
    try {
      final list = await repository.conversations(search: search, page: cp);
      if (!_disposed &&
          search == conversationSearch &&
          cp == conversationPage) {
        conversations = list.items;
        conversationPages = list.totalPages;
        if (cp > (list.totalPages < 1 ? 1 : list.totalPages)) {
          conversationPage = list.totalPages < 1 ? 1 : list.totalPages;
          scheduleMicrotask(_refreshAfterCurrent);
        }
        final updated = conversations
            .where((c) => c.id == selected?.id)
            .firstOrNull;
        if (updated != null) selected = updated;
      }
      if (id != null || starred) {
        late final PageResult<Message> history;
        if (starred) {
          history = await repository.favorites(search: mq, page: mp);
        } else {
          final window = messageHistory;
          // Capture the selected window before awaiting, then validate version below.
          if (version != _selectionVersion) return;
          await window.refresh();
          history = PageResult(window.items, 1, window.totalPages);
        }
        if (!_disposed && version == _selectionVersion) {
          messages = history.items;
          messagePages = history.totalPages;
          if (!starred &&
              mq.isEmpty &&
              mp == 1 &&
              ((selected?.unreadCount ?? 0) > 0 ||
                  history.items.any((m) => m.isRead == false))) {
            await _markRead(id!, version);
          }
          if (_disposed || version != _selectionVersion) return;
          if (starred &&
              mp > (history.totalPages < 1 ? 1 : history.totalPages)) {
            messagePage = history.totalPages < 1 ? 1 : history.totalPages;
            scheduleMicrotask(_refreshAfterCurrent);
          }
        }
      }
      if (!_disposed) {
        error = null;
        lastSynced = DateTime.now();
      }
    } catch (e) {
      if (e is ApiException &&
          e.status == 404 &&
          version == _selectionVersion) {
        selected = null;
        messages = [];
      }
      await _handle(e, message: failureMessage);
    } finally {
      refreshing = false;
      _notify();
      if (_refreshPending) _queueRefresh();
    }
  }

  Future<void> select(Conversation? conversation) async {
    favoritesMode = false;
    _selectionVersion++;
    selected = conversation;
    messageSearch = '';
    messagePage = 1;
    messagePages = 0;
    messages = conversation == null ? [] : messageHistory.items;
    _notify();
    // An old refresh cannot update the new selection; request its history separately.
    if (conversation == null) return;
    final version = _selectionVersion;
    try {
      final history = messageHistory;
      await history.refresh();
      final result = PageResult(history.items, 1, history.totalPages);
      if (!_disposed && version == _selectionVersion) {
        messages = result.items;
        messagePages = result.totalPages;
        _notify();
        if (conversation.unreadCount > 0 ||
            result.items.any((m) => m.isRead == false)) {
          await _markRead(conversation.id, version);
        }
      }
    } catch (e) {
      if (version == _selectionVersion) await _handle(e);
    }
  }

  Future<void> _markRead(String id, int version) async {
    if (_disposed || version != _selectionVersion || selected?.id != id) return;
    await repository.markRead(id);
    if (_disposed) return;
    conversations = conversations
        .map((c) => c.id == id ? c.withUnreadCount(0) : c)
        .toList();
    if (selected?.id == id) selected = selected!.withUnreadCount(0);
    _notify();
  }

  Future<void> searchConversations(String search) async {
    conversationSearch = search.trim();
    conversationPage = 1;
    await _refreshAfterCurrent();
  }

  Future<void> searchMessages(String search) async {
    messageSearch = search.trim();
    messagePage = 1;
    _selectionVersion++;
    if (!favoritesMode && selected != null) messages = messageHistory.items;
    _notify();
    await _refreshAfterCurrent();
  }

  Future<void> pageConversations(int page) async {
    conversationPage = page;
    await _refreshAfterCurrent();
  }

  Future<void> pageMessages(int page) async {
    messagePage = page;
    _selectionVersion++;
    await _refreshAfterCurrent();
  }

  Future<void> _refreshAfterCurrent({String? failureMessage}) async {
    while (refreshing && !_disposed) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
    if (!_disposed) await refresh(failureMessage: failureMessage);
  }

  Future<void> _mutate(
    Future<void> Function() work, {
    String? refreshFailureMessage,
  }) async {
    if (busy) return;
    busy = true;
    error = null;
    _notify();
    try {
      await work();
    } catch (e) {
      await _handle(e);
    } finally {
      busy = false;
      _notify();
      if (_refreshPending) _queueRefresh();
    }
    if (error == null) {
      await _refreshAfterCurrent(failureMessage: refreshFailureMessage);
    }
  }

  Future<void> create(String title) => _mutate(() async {
    final c = await repository.create(title);
    conversationSearch = '';
    conversationPage = 1;
    await select(c);
  });
  Future<void> rename(String title, {Conversation? conversation}) =>
      _mutate(() async {
        final id = conversation?.id ?? selected?.id;
        if (id == null) return;
        final c = await repository.rename(id, title);
        if (selected?.id == id) selected = c;
      });
  Future<void> deleteConversation({Conversation? conversation}) =>
      _mutate(() async {
        final id = conversation?.id ?? selected?.id;
        if (id == null) return;
        await repository.remove(id);
        drafts.remove(id);
        imageDrafts.remove(id);
        fileDrafts.remove(id);
        _sendAttempts.remove(id);
        _histories.removeWhere((key, _) => key.startsWith('$id:'));
        if (selected?.id == id) await select(null);
      });
  Future<void> send(String content) => _mutate(() async {
    final id = selected?.id;
    if (id == null) return;
    final files = fileDrafts[id] ?? <XFile>[];
    final image = files.isEmpty ? imageDrafts[id] : null;
    if (content.trim().isEmpty && image == null && files.isEmpty) return;
    if (content.runes.length > 50000) throw const ApiException('正文最多 50,000 字');
    final candidate = await _SendAttempt.capture(content.trim(), image, files);
    final previous = _sendAttempts[id];
    final attempt = previous != null && previous.matches(candidate)
        ? previous
        : candidate;
    _sendAttempts[id] = attempt;
    final clientId = attempt.clientId;
    if (files.isNotEmpty) {
      await repository.api.sendFiles(
        id,
        attempt.uploadFiles,
        attempt.content,
        clientId,
      );
    } else if (image != null) {
      await repository.api.sendImage(
        id,
        attempt.image!,
        attempt.content,
        clientId,
      );
    } else {
      await repository.send(id, content.trim(), clientId: clientId);
    }
    _sendAttempts.remove(id);
    if (identical(imageDrafts[id], image)) imageDrafts.remove(id);
    if (identical(fileDrafts[id], files)) fileDrafts.remove(id);
    if (drafts[id] == content) drafts.remove(id);
    if (selected?.id == id) {
      messagePage = 1;
      messageSearch = '';
      _selectionVersion++;
      messageHistory.atBottom = true;
      messageHistory.scrollOffset = 0;
      messageHistory.pivotId = null;
      scrollToLatest++;
    }
  }, refreshFailureMessage: '消息已发送，列表刷新失败，请刷新查看。');
  Future<void> annotate(Message message, String text) async {
    if (busy) throw ApiException('请等待当前操作完成');
    if (text.trim().runes.length > 2000) throw ApiException('批注最多 2000 字');
    busy = true;
    _notify();
    try {
      await repository.annotate(message, text);
    } catch (e) {
      await _handle(e);
      rethrow;
    } finally {
      busy = false;
      _notify();
      if (_refreshPending) _queueRefresh();
    }
    await _refreshAfterCurrent();
  }

  Future<void> pin(Conversation conversation) =>
      _mutate(() => repository.pin(conversation));
  Future<void> deleteMessage(Message message) =>
      _mutate(() => repository.deleteMessage(message));
  Future<void> star(Message message) => _mutate(() => repository.star(message));
  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _eventRefresh?.cancel();
    _reconnect?.cancel();
    unawaited(_eventSubscription?.cancel());
    _eventConnection?.close();
    _eventsActive = false;
    _eventGeneration++;
    super.dispose();
  }
}

class _SendAttempt {
  _SendAttempt(this.content, this.image, this.files);
  final String clientId = generateInstallationId();
  final String content;
  final Uint8List? image;
  final List<({String name, Uint8List bytes})> files;

  static Future<_SendAttempt> capture(
    String content,
    Uint8List? image,
    List<XFile> files,
  ) async {
    if (files.length > 5) throw const ApiException('最多选择 5 个文件');
    final captured = <({String name, Uint8List bytes})>[];
    var total = 0;
    for (final file in files) {
      total += await file.length();
      if (total > 20 * 1024 * 1024) throw const ApiException('附件合计不能超过 20 MB');
      final bytes = await file.readAsBytes();
      captured.add((name: file.name, bytes: bytes));
    }
    return _SendAttempt(
      content,
      image == null ? null : Uint8List.fromList(image),
      captured,
    );
  }

  bool matches(_SendAttempt other) {
    if (content != other.content ||
        !listEquals(image, other.image) ||
        files.length != other.files.length) {
      return false;
    }
    for (var i = 0; i < files.length; i++) {
      if (files[i].name != other.files[i].name ||
          !listEquals(files[i].bytes, other.files[i].bytes)) {
        return false;
      }
    }
    return true;
  }

  List<XFile> get uploadFiles =>
      files.map((file) => XFile.fromData(file.bytes, name: file.name)).toList();
}
