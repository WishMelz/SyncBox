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
  bool filesMode = false;
  bool devicesOpen = false;
  bool settingsOpen = false;
  int favoritesRevision = 0;
  int filesRevision = 0;
  int devicesRevision = 0;
  int settingsRevision = 0;
  String? currentDeviceId;
  DateTime? lastSynced;
  UploadProgress? uploadProgress;
  UploadCancelToken? _uploadCancelToken;
  final Map<String, List<XFile>> fileDrafts = {};
  final Map<String, _SendAttempt> _sendAttempts = {};
  final Map<String, MessageHistory> _histories = {};
  int scrollToLatest = 0;
  String get historyKey => '${selected?.id ?? ''}:$messageSearch';
  MessageHistory get messageHistory {
    final key = historyKey, id = selected?.id ?? '', query = messageSearch;
    if (!_histories.containsKey(key)) {
      _histories[key] = MessageHistory(
        ({before, since, includeTotal = true}) => repository.messages(
          id,
          search: query,
          before: before,
          since: since,
          includeTotal: includeTotal,
        ),
      );
      if (_histories.length > 20) _histories.remove(_histories.keys.first);
    }
    return _histories[key]!;
  }

  Future<void> loadOlderMessages() async {
    if (selected == null || favoritesMode || filesMode) return;
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

  void cancelUpload() {
    _uploadCancelToken?.cancel();
  }

  void setDevicesOpen(bool open) {
    if (devicesOpen == open) return;
    devicesOpen = open;
    if (open) devicesRevision++;
    _notify();
  }

  void setSettingsOpen(bool open) {
    if (settingsOpen == open) return;
    settingsOpen = open;
    if (open) settingsRevision++;
    _notify();
  }

  Future<void> showFavorites() async {
    _selectionVersion++;
    favoritesMode = true;
    filesMode = false;
    selected = null;
    messages = [];
    messageSearch = '';
    messagePage = 1;
    messagePages = 0;
    favoritesRevision++;
    _notify();
    await _refreshAfterCurrent();
  }

  Future<void> showFiles() async {
    _selectionVersion++;
    favoritesMode = false;
    filesMode = true;
    selected = null;
    messages = [];
    messageSearch = '';
    messagePage = 1;
    messagePages = 0;
    filesRevision++;
    _notify();
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
  Timer? _timer, _reconnect, _eventRefresh, _reconcileTimer;
  SyncEventConnection? _eventConnection;
  StreamSubscription<Map<String, dynamic>>? _eventSubscription;
  bool _eventsActive = false, realtimeConnected = false;
  bool _pendingRefresh = false, _pendingRefreshReconcile = false;
  bool _pendingEventBatch = false, _pendingEventReconcile = false;
  final Set<String> _pendingScopes = {};
  final Set<String> _pendingConversationIds = {};
  final Map<String, Set<String>> _pendingMessageIdsByConversation = {};
  final Set<String> _pendingWildcardMessageConversations = {};
  bool _pendingHasGlobalWildcardMessage = false;
  int _eventGeneration = 0, _retrySeconds = 3;
  void start() => setActive(true);

  void _clearPendingEvents() {
    _pendingEventBatch = false;
    _pendingEventReconcile = false;
    _pendingScopes.clear();
    _pendingConversationIds.clear();
    _pendingMessageIdsByConversation.clear();
    _pendingWildcardMessageConversations.clear();
    _pendingHasGlobalWildcardMessage = false;
  }

  void setActive(bool active) {
    if (_disposed || _eventsActive == active) return;
    _eventsActive = active;
    _eventGeneration++;
    _timer?.cancel();
    _reconnect?.cancel();
    _eventRefresh?.cancel();
    _reconcileTimer?.cancel();
    unawaited(_eventSubscription?.cancel());
    _eventConnection?.close();
    _eventConnection = null;
    realtimeConnected = false;
    _pendingRefresh = false;
    _pendingRefreshReconcile = false;
    _clearPendingEvents();
    if (active) {
      _retrySeconds = 3;
      _setPolling();
      _reconcileTimer = Timer.periodic(
        const Duration(minutes: 5),
        (_) => unawaited(refresh(reconcile: true)),
      );
      _connectEvents(_eventGeneration);
      unawaited(refresh(reconcile: true));
    }
    _notify();
  }

  void _setPolling() {
    _timer?.cancel();
    if (_eventsActive) {
      _timer = Timer.periodic(
        Duration(seconds: realtimeConnected ? 30 : 5),
        (_) => unawaited(refresh(reconcile: false)),
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
          _queueFullReconcile(); // Catch up changes made while disconnected.
        } else if (event['type'] == 'invalidate') {
          _recordInvalidation(event);
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

  void _queueFullReconcile() {
    if (_disposed || !_eventsActive) return;
    _pendingEventBatch = true;
    _pendingEventReconcile = true;
    _scheduleEventFlush();
  }

  void _recordInvalidation(Map<String, dynamic> event) {
    if (_disposed || !_eventsActive) return;
    final scope = event['scope']?.toString();
    if (scope == null || scope.isEmpty) {
      _queueFullReconcile();
      return;
    }
    _pendingEventBatch = true;
    _pendingScopes.add(scope);
    final conversationId = event['conversationId']?.toString();
    if (conversationId != null && conversationId.isNotEmpty) {
      _pendingConversationIds.add(conversationId);
    }
    if (scope == 'messages') {
      if (conversationId != null && conversationId.isNotEmpty) {
        final messageId = event['messageId']?.toString();
        if (messageId != null && messageId.isNotEmpty) {
          _pendingMessageIdsByConversation
              .putIfAbsent(conversationId, () => <String>{})
              .add(messageId);
        } else {
          _pendingWildcardMessageConversations.add(conversationId);
        }
      } else {
        _pendingHasGlobalWildcardMessage = true;
      }
    }
    _scheduleEventFlush();
  }

  void _scheduleEventFlush() {
    if (_disposed || !_eventsActive) return;
    // Keep a single pending flush even while a request or mutation is running.
    if (_eventRefresh?.isActive == true) return;
    _eventRefresh = Timer(const Duration(milliseconds: 150), () {
      if (!_disposed && _eventsActive) unawaited(_flushEvents());
    });
  }

  Future<void> _flushEvents() async {
    if (_disposed || !_eventsActive) return;
    if (refreshing || busy) return;
    final runFullRefresh = _pendingRefresh || _pendingEventReconcile;
    final runFullReconcile = _pendingRefreshReconcile || _pendingEventReconcile;
    final scopes = Set<String>.from(_pendingScopes);
    final conversationIds = Set<String>.from(_pendingConversationIds);
    final messageIdsByConversation = <String, Set<String>>{
      for (final entry in _pendingMessageIdsByConversation.entries)
        entry.key: Set<String>.from(entry.value),
    };
    final wildcardMessageConversations = Set<String>.from(
      _pendingWildcardMessageConversations,
    );
    final hasGlobalWildcardMessage = _pendingHasGlobalWildcardMessage;

    _pendingRefresh = false;
    _pendingRefreshReconcile = false;
    _clearPendingEvents();

    if (runFullRefresh) {
      await refresh(reconcile: runFullReconcile);
      return;
    }
    if (scopes.isEmpty) return;

    final refreshConversations = scopes.contains('conversations');
    final selectedId = selected?.id;
    var historyAction = _HistorySyncAction.none;
    List<String> fetchMessageIds = const [];

    if (selectedId != null && !favoritesMode && !filesMode) {
      final selectedConvInvalidated =
          refreshConversations && conversationIds.contains(selectedId);
      final hasWildcard =
          hasGlobalWildcardMessage ||
          wildcardMessageConversations.contains(selectedId);
      final ids = messageIdsByConversation[selectedId];
      if (hasWildcard || selectedConvInvalidated) {
        historyAction = _HistorySyncAction.refreshLatest;
      } else if (ids != null && ids.isNotEmpty) {
        final historyReady = _histories[historyKey]?.ready == true;
        if (messageSearch.isEmpty && historyReady && ids.length <= 3) {
          historyAction = _HistorySyncAction.fetchMessages;
          fetchMessageIds = ids.toList();
        } else {
          historyAction = _HistorySyncAction.refreshLatest;
        }
      }
    }

    final refreshFavorites = favoritesMode && scopes.contains('favorites');
    final notifyFiles =
        filesMode &&
        (scopes.contains('messages') ||
            scopes.contains('conversations') ||
            scopes.contains('settings'));
    final notifyDevices = devicesOpen && scopes.contains('devices');
    final notifySettings = settingsOpen && scopes.contains('settings');

    if (notifyFiles) filesRevision++;
    if (notifyDevices) devicesRevision++;
    if (notifySettings) settingsRevision++;

    final needsNetwork =
        refreshConversations ||
        historyAction != _HistorySyncAction.none ||
        refreshFavorites;

    if (!needsNetwork) {
      if (notifyFiles || notifyDevices || notifySettings) {
        _notify();
      }
      return;
    }

    refreshing = true;
    _notify();
    final version = _selectionVersion,
        id = selected?.id,
        search = conversationSearch,
        cp = conversationPage,
        mp = messagePage,
        mq = messageSearch;
    try {
      if (refreshConversations) {
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
      }

      if (id != null && !favoritesMode && !filesMode) {
        final window = messageHistory;
        if (historyAction == _HistorySyncAction.fetchMessages) {
          for (final messageId in fetchMessageIds) {
            if (_disposed || version != _selectionVersion) break;
            try {
              final detail = await repository.messageDetail(messageId);
              if (!_disposed &&
                  version == _selectionVersion &&
                  (detail.conversationId == null ||
                      detail.conversationId == id)) {
                window.upsertMessage(detail);
              }
            } on ApiException catch (e) {
              if (e.status == 404) {
                window.removeMessage(messageId);
                repository.api.mediaCache.invalidateMessage(messageId);
              } else {
                rethrow;
              }
            }
          }
          if (!_disposed && version == _selectionVersion) {
            messages = window.items;
            messagePages = window.totalPages;
            if (mq.isEmpty &&
                mp == 1 &&
                ((selected?.unreadCount ?? 0) > 0 ||
                    window.items.any((m) => m.isRead == false))) {
              await _markRead(id, version);
            }
          }
        } else if (historyAction == _HistorySyncAction.refreshLatest) {
          if (version == _selectionVersion) {
            await window.refreshLatest();
            if (!_disposed && version == _selectionVersion) {
              messages = window.items;
              messagePages = window.totalPages;
              if (mq.isEmpty &&
                  mp == 1 &&
                  ((selected?.unreadCount ?? 0) > 0 ||
                      window.items.any((m) => m.isRead == false))) {
                await _markRead(id, version);
              }
            }
          }
        }
      }

      if (refreshFavorites && !_disposed && version == _selectionVersion) {
        final history = await repository.favorites(search: mq, page: mp);
        if (!_disposed && version == _selectionVersion) {
          messages = history.items;
          messagePages = history.totalPages;
          favoritesRevision++;
          if (mp > (history.totalPages < 1 ? 1 : history.totalPages)) {
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
      await _handle(e);
    } finally {
      refreshing = false;
      _notify();
      if (_pendingRefresh || _pendingEventBatch) _scheduleEventFlush();
    }
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

  Future<void> refresh({String? failureMessage, bool reconcile = true}) async {
    if (_disposed) return;
    if (refreshing || busy) {
      _pendingRefresh = true;
      if (reconcile) _pendingRefreshReconcile = true;
      return;
    }
    _pendingRefresh = false;
    _pendingRefreshReconcile = false;
    if (reconcile) _clearPendingEvents();
    refreshing = true;
    _notify();
    final version = _selectionVersion,
        id = selected?.id,
        search = conversationSearch,
        cp = conversationPage,
        mp = messagePage,
        mq = messageSearch,
        starred = favoritesMode,
        files = filesMode;
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
      if ((id != null || starred) && !files) {
        late final PageResult<Message> history;
        if (starred) {
          history = await repository.favorites(search: mq, page: mp);
        } else {
          final window = messageHistory;
          // Capture the selected window before awaiting, then validate version below.
          if (version != _selectionVersion) return;
          if (reconcile) {
            await window.reconcile();
          } else {
            await window.refreshLatest();
          }
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
      if (files && reconcile && !_disposed && version == _selectionVersion) {
        filesRevision++;
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
      if (_pendingRefresh || _pendingEventBatch) _scheduleEventFlush();
    }
  }

  Future<void> select(Conversation? conversation) async {
    favoritesMode = false;
    filesMode = false;
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
      await history.refreshLatest();
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

  Future<void> _refreshAfterCurrent({
    String? failureMessage,
    bool reconcile = false,
  }) async {
    while (refreshing && !_disposed) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
    if (!_disposed) {
      await refresh(failureMessage: failureMessage, reconcile: reconcile);
    }
  }

  Future<void> _mutate(
    Future<void> Function() work, {
    String? refreshFailureMessage,
  }) async {
    if (busy) return;
    busy = true;
    error = null;
    var cancelled = false;
    _notify();
    try {
      await work();
    } on UploadCancelledException {
      cancelled = true;
    } catch (e) {
      await _handle(e);
    } finally {
      busy = false;
      _notify();
      if (_pendingRefresh || _pendingEventBatch) _scheduleEventFlush();
    }
    if (error == null && !cancelled) {
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
        repository.api.mediaCache.clear();
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
      final token = UploadCancelToken();
      _uploadCancelToken = token;
      uploadProgress = UploadProgress(loaded: 0, total: attempt.totalBytes);
      _notify();
      try {
        await repository.api.sendFiles(
          id,
          attempt.files,
          attempt.content,
          clientId,
          (progress) {
            if (_disposed) return;
            uploadProgress = progress;
            _notify();
          },
          token,
        );
      } finally {
        if (identical(_uploadCancelToken, token)) {
          _uploadCancelToken = null;
          uploadProgress = null;
        }
      }
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
    // Sending disables the composer, so the draft cannot change while the
    // request is in flight. Always clear it after a successful delivery,
    // including when the user entered trailing whitespace.
    drafts.remove(id);
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
      if (_pendingRefresh || _pendingEventBatch) _scheduleEventFlush();
    }
    await _refreshAfterCurrent();
  }

  Future<void> editMessage(Message message, String content) =>
      _mutate(() => repository.editMessage(message, content));

  Future<void> deleteAttachment(Message message, Attachment file) =>
      _mutate(() => repository.deleteAttachment(message, file));

  Future<void> deleteImage(Message message) =>
      _mutate(() => repository.deleteImage(message));

  Future<void> pin(Conversation conversation) =>
      _mutate(() => repository.pin(conversation));
  Future<void> deleteMessage(Message message) =>
      _mutate(() => repository.deleteMessage(message));
  Future<void> star(Message message) => _mutate(() => repository.star(message));
  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _reconcileTimer?.cancel();
    _eventRefresh?.cancel();
    _reconnect?.cancel();
    _uploadCancelToken?.cancel();
    unawaited(_eventSubscription?.cancel());
    _eventConnection?.close();
    _eventsActive = false;
    _eventGeneration++;
    super.dispose();
  }
}

enum _HistorySyncAction { none, refreshLatest, fetchMessages }

class _AttemptFile {
  const _AttemptFile({
    required this.name,
    required this.path,
    required this.size,
    this.modified,
    this.bytes,
  });

  final String name;
  final String path;
  final int size;
  final DateTime? modified;
  final Uint8List? bytes;
}

class _SendAttempt {
  _SendAttempt(
    this.content,
    this.image,
    this.descriptors,
    this.files,
    this.totalBytes,
  );
  final String clientId = generateInstallationId();
  final String content;
  final Uint8List? image;
  final List<_AttemptFile> descriptors;
  final List<UploadFile> files;
  final int totalBytes;

  static Future<_SendAttempt> capture(
    String content,
    Uint8List? image,
    List<XFile> files,
  ) async {
    if (files.length > 5) throw const ApiException('最多选择 5 个文件');
    final descriptors = <_AttemptFile>[];
    final uploadFiles = <UploadFile>[];
    var total = 0;
    for (final file in files) {
      if (file.path.isNotEmpty) {
        final len = await file.length();
        if (len == 0) throw const ApiException('不能发送空文件');
        if (len > 20 * 1024 * 1024 - total) {
          throw const ApiException('附件合计不能超过 20 MB');
        }
        total += len;
        DateTime? modified;
        try {
          modified = await file.lastModified();
        } catch (_) {}
        descriptors.add(
          _AttemptFile(
            name: file.name,
            path: file.path,
            size: len,
            modified: modified,
          ),
        );
        uploadFiles.add(UploadFile.xfile(name: file.name, size: len, file: file));
      } else {
        final bytes = await file.readAsBytes();
        if (bytes.isEmpty) throw const ApiException('不能发送空文件');
        if (bytes.length > 20 * 1024 * 1024 - total) {
          throw const ApiException('附件合计不能超过 20 MB');
        }
        total += bytes.length;
        descriptors.add(
          _AttemptFile(
            name: file.name,
            path: '',
            size: bytes.length,
            bytes: bytes,
          ),
        );
        uploadFiles.add(UploadFile.bytes(name: file.name, bytes: bytes));
      }
    }
    return _SendAttempt(
      content,
      image == null ? null : Uint8List.fromList(image),
      descriptors,
      uploadFiles,
      total,
    );
  }

  bool matches(_SendAttempt other) {
    if (content != other.content ||
        !listEquals(image, other.image) ||
        descriptors.length != other.descriptors.length) {
      return false;
    }
    for (var i = 0; i < descriptors.length; i++) {
      final a = descriptors[i];
      final b = other.descriptors[i];
      if (a.name != b.name ||
          a.path != b.path ||
          a.size != b.size ||
          a.modified != b.modified ||
          !listEquals(a.bytes, b.bytes)) {
        return false;
      }
    }
    return true;
  }
}
