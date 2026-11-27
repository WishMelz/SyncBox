import {
  useCallback,
  useEffect,
  useLayoutEffect,
  useRef,
  useState,
  type CSSProperties,
  type FormEvent,
} from 'react';
import {
  ArrowLeft,
  ChevronLeft,
  ChevronRight,
  Pencil,
  Pin,
  Plus,
  Search,
  Trash2,
  X,
} from 'lucide-react';
import { ActionMenu } from '@/components/ui/action-menu';
import { Button } from '@/components/ui/button';
import { ConfirmDialog } from '@/components/ui/confirm-dialog';
import { MobileWorkspaceNav } from '@/components/layout/mobile-workspace-nav';
import { AnnotationDialog } from '@/components/chat/annotation-dialog';
import { FavoritesPanel } from '@/components/chat/favorites-panel';
import { FilesPanel } from '@/components/chat/files-panel';
import { VirtualMessageFeed } from '@/components/chat/virtual-message-feed';
import { SettingsPanel } from '@/components/settings/settings-panel';
import { ConversationSidebar } from '@/components/workspace/conversation-sidebar';
import { MessageComposer } from '@/components/workspace/message-composer';
import { DevicesDialog } from '@/components/workspace/devices-dialog';
import { validateAttachments } from '@/lib/attachments';
import { mediaCache } from '@/lib/media-cache';
import { SendAttempts } from '@/lib/send-attempts';
import { planSyncActions, type SyncBatch } from '@/lib/sync-events';
import { useDeviceHeartbeat } from '@/hooks/use-device-heartbeat';
import { useMessageHistory } from '@/hooks/use-message-history';
import { useSyncEvents } from '@/hooks/use-sync-events';
import { ApiError } from '@/services/api';
import { uploadAttachments, type UploadProgress } from '@/services/attachments';
import type { Session } from '@/services/auth';
import { conversationsApi, type Conversation, type Page } from '@/services/conversations';
import { devicesApi, type Device } from '@/services/devices';
import { messagesApi, type Message } from '@/services/messages';

export function WorkspacePage({
  session,
  onLogout,
  onExpired,
}: {
  session: Session;
  onLogout: () => Promise<void>;
  onExpired: () => void;
}) {
  const token = session.accessToken;
  const [dialogTarget, setDialogTarget] = useState<Conversation | null>(null);
  const [scrollRequest, setScrollRequest] = useState(0);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [settingsLocked, setSettingsLocked] = useState(false);
  const [compact, setCompact] = useState(() => window.matchMedia('(max-width: 767px)').matches);
  useEffect(() => {
    const media = window.matchMedia('(max-width: 767px)');
    const update = () => setCompact(media.matches);
    media.addEventListener('change', update);
    return () => media.removeEventListener('change', update);
  }, []);
  const [messageSearchOpen, setMessageSearchOpen] = useState(false);
  const [listLoading, setListLoading] = useState(true);
  const [messageConnected, setMessageConnected] = useState(true);
  const [lastSyncedAt, setLastSyncedAt] = useState<number | null>(null);
  const [lastSyncOk, setLastSyncOk] = useState(true);
  const [feedError, setFeedError] = useState('');
  const [annotationTarget, setAnnotationTarget] = useState<Message | null>(null);
  const [annotationRevision, setAnnotationRevision] = useState(0);
  const [favoritesOpen, setFavoritesOpen] = useState(false);
  const [favoritesSyncRevision, setFavoritesSyncRevision] = useState(0);
  const [filesOpen, setFilesOpen] = useState(false);
  const [filesSyncRevision, setFilesSyncRevision] = useState(0);
  const [settingsSyncRevision, setSettingsSyncRevision] = useState(0);
  const [pinBusy, setPinBusy] = useState(false);
  const [conversations, setConversations] = useState<Page<Conversation>>({
    items: [],
    total: 0,
    page: 1,
    totalPages: 0,
  });
  const [selected, setSelected] = useState<Conversation | null>(null);
  const [search, setSearch] = useState(''),
    [query, setQuery] = useState(''),
    [messageQuery, setMessageQuery] = useState(''),
    [messageSearch, setMessageSearch] = useState(''),
    [searchResultIndex, setSearchResultIndex] = useState(0);
  const [page, setPage] = useState(1),
    [drafts, setDrafts] = useState<Record<string, string>>({});
  const feed = useMessageHistory(token, selected?.id, messageQuery);
  const messages = feed.state.data,
    loading = feed.state.loading;
  const searchResults = messageQuery ? messages.items : [];
  const focusedSearchMessage = searchResults[searchResultIndex]?.id;
  const [error, setError] = useState(''),
    [busy, setBusy] = useState(false);
  const [dialog, setDialog] = useState<'create' | 'rename' | 'delete' | 'devices' | null>(null),
    [name, setName] = useState(''),
    [devices, setDevices] = useState<Device[]>([]),
    [deviceEdit, setDeviceEdit] = useState<string | null>(null),
    [deviceName, setDeviceName] = useState('');
  const [deviceToRemove, setDeviceToRemove] = useState<Device | null>(null);
  const [attachments, setAttachments] = useState<Record<string, File[]>>({});
  const [sendNotices, setSendNotices] = useState<Record<string, { text: string; failed: boolean }>>(
    {},
  );
  const sendAttempts = useRef(new SendAttempts());
  const sendVersions = useRef<Record<string, number>>({});
  const [uploadProgress, setUploadProgress] = useState<UploadProgress | null>(null);
  const [dragging, setDragging] = useState(false);
  const [viewportHeight, setViewportHeight] = useState<number>();
  const dragDepth = useRef(0);
  const uploadController = useRef<AbortController | null>(null);
  const conversationListController = useRef<AbortController | null>(null);
  const conversationListRevision = useRef(0);
  useEffect(() => () => uploadController.current?.abort(), []);
  useEffect(() => () => conversationListController.current?.abort(), []);
  useDeviceHeartbeat(token);

  const fileInput = useRef<HTMLInputElement>(null);
  const imageInput = useRef<HTMLInputElement>(null);
  const messageInput = useRef<HTMLTextAreaElement>(null);
  const messageSearchInput = useRef<HTMLInputElement>(null);
  useLayoutEffect(() => {
    const input = messageInput.current;
    if (!input) return;
    input.style.height = 'auto';
    input.style.height = `${Math.min(input.scrollHeight, 180)}px`;
  }, [selected?.id, drafts[selected?.id ?? '']]);
  useEffect(() => {
    if (messageSearchOpen) messageSearchInput.current?.focus();
  }, [messageSearchOpen]);
  useEffect(() => {
    const viewport = window.visualViewport;
    const resize = () => {
      setViewportHeight(
        window.innerWidth < 768 && viewport?.scale === 1 ? viewport.height : undefined,
      );
    };
    resize();
    viewport?.addEventListener('resize', resize);
    window.addEventListener('resize', resize);
    return () => {
      viewport?.removeEventListener('resize', resize);
      window.removeEventListener('resize', resize);
    };
  }, []);

  const sendLock = useRef(false);
  const selectedRef = useRef(selected?.id);
  selectedRef.current = selected?.id;
  const uiStateRef = useRef({
    selectedId: selected?.id ?? null,
    isSearchingMessages: !!messageQuery,
    isHistoryReady: feed.state.ready,
    favoritesOpen,
    filesOpen,
    devicesOpen: dialog === 'devices',
    settingsOpen,
  });
  uiStateRef.current = {
    selectedId: selected?.id ?? null,
    isSearchingMessages: !!messageQuery,
    isHistoryReady: feed.state.ready,
    favoritesOpen,
    filesOpen,
    devicesOpen: dialog === 'devices',
    settingsOpen,
  };

  const fail = useCallback(
    (e: unknown) => {
      if (e instanceof ApiError && e.status === 401) {
        onExpired();
        return;
      }
      setError(e instanceof ApiError ? e.message : '操作失败，请重试');
    },
    [onExpired],
  );

  useEffect(() => {
    const id = setTimeout(() => {
      setQuery(search);
      setPage(1);
    }, 300);
    return () => clearTimeout(id);
  }, [search]);
  useEffect(() => {
    const id = setTimeout(() => {
      setMessageQuery(messageSearch);
    }, 300);
    return () => clearTimeout(id);
  }, [messageSearch]);
  useEffect(() => {
    setSearchResultIndex(0);
  }, [messageQuery, selected?.id]);

  const loadMessages = useCallback(
    async (mode: 'latest' | 'reconcile' = 'reconcile') => {
      if (!selected) return;
      const id = selected.id;
      try {
        if (mode === 'reconcile') {
          await feed.history.reconcile();
        } else {
          await feed.history.refreshLatest();
        }
        if (selectedRef.current === id) {
          setMessageConnected(true);
          setFeedError('');
          setLastSyncedAt(Date.now());
        }
      } catch (e) {
        if (selectedRef.current === id) {
          if (e instanceof ApiError && e.status === 404) setSelected(null);
          setMessageConnected(false);
          setFeedError('消息加载失败，请重试');
          if (e instanceof ApiError && e.status === 401) fail(e);
        }
      }
    },
    [feed.history, selected?.id, fail],
  );

  const refresh = useCallback(async () => {
    conversationListController.current?.abort();
    const controller = new AbortController();
    conversationListController.current = controller;
    const revision = ++conversationListRevision.current;
    try {
      const result = await conversationsApi.list(token, query, page, controller.signal);
      if (controller.signal.aborted || revision !== conversationListRevision.current) return;
      setConversations(result);
      setSelected((current) =>
        current ? (result.items.find((c) => c.id === current.id) ?? current) : current,
      );
      setLastSyncOk(true);
      setLastSyncedAt(Date.now());
    } catch (e) {
      if (controller.signal.aborted || revision !== conversationListRevision.current) return;
      setLastSyncOk(false);
      throw e;
    } finally {
      if (conversationListController.current === controller) {
        conversationListController.current = null;
      }
      if (revision === conversationListRevision.current) setListLoading(false);
    }
  }, [token, query, page]);

  const refreshRef = useRef(refresh);
  refreshRef.current = refresh;
  const loadMessagesRef = useRef(loadMessages);
  loadMessagesRef.current = loadMessages;

  const applySingleMessageEvents = useCallback(
    async (targetConversationId: string, messageIds: string[]) => {
      for (const messageId of messageIds) {
        if (selectedRef.current !== targetConversationId) return;
        try {
          const updated = await messagesApi.detail(token, messageId);
          if (selectedRef.current !== targetConversationId) return;
          if (updated.conversationId !== targetConversationId) {
            feed.history.removeMessage(messageId);
            continue;
          }
          const prev = feed.history.state.data.items.find((item) => item.id === updated.id);
          if (
            prev &&
            (Boolean(prev.image) !== Boolean(updated.image) ||
              (prev.attachments?.length ?? 0) !== (updated.attachments?.length ?? 0) ||
              prev.filesExpired !== updated.filesExpired)
          ) {
            mediaCache.invalidateMessage(updated.id);
          }
          feed.history.upsertMessage(updated);
          setMessageConnected(true);
          setFeedError('');
          setLastSyncedAt(Date.now());
        } catch (e) {
          if (e instanceof ApiError && e.status === 401) {
            fail(e);
            return;
          }
          if (e instanceof ApiError && e.status === 404) {
            mediaCache.invalidateMessage(messageId);
            feed.history.removeMessage(messageId);
            setLastSyncedAt(Date.now());
            continue;
          }
          await loadMessagesRef.current('latest');
          return;
        }
      }
    },
    [token, feed.history, fail],
  );

  const handleSyncBatch = useCallback(
    (batch: SyncBatch) => {
      setLastSyncOk(true);
      setLastSyncedAt(Date.now());
      const state = uiStateRef.current;
      const plan = planSyncActions(batch, {
        selectedConversationId: state.selectedId,
        isSearchingMessages: state.isSearchingMessages,
        isHistoryReady: state.isHistoryReady,
        favoritesOpen: state.favoritesOpen,
        filesOpen: state.filesOpen,
        devicesOpen: state.devicesOpen,
        settingsOpen: state.settingsOpen,
      });

      if (plan.refreshConversations) {
        void refreshRef.current().catch((error) => {
          if (error instanceof ApiError && error.status === 401) fail(error);
        });
      }
      if (plan.selectedHistory.type === 'refreshLatest') {
        void loadMessagesRef.current('latest');
      } else if (plan.selectedHistory.type === 'fetchMessages' && state.selectedId) {
        void applySingleMessageEvents(state.selectedId, plan.selectedHistory.messageIds);
      }
      if (plan.refreshFavorites) {
        setFavoritesSyncRevision((value) => value + 1);
      }
      if (plan.refreshFiles) {
        setFilesSyncRevision((value) => value + 1);
      }
      if (plan.refreshDevices) {
        void devicesApi
          .list(token)
          .then(setDevices)
          .catch((error) => {
            if (error instanceof ApiError && error.status === 401) fail(error);
          });
      }
      if (plan.refreshSettings) {
        setSettingsSyncRevision((value) => value + 1);
      }
    },
    [token, applySingleMessageEvents, fail],
  );

  const handleReconnect = useCallback(() => {
    setLastSyncOk(true);
    setLastSyncedAt(Date.now());
    void refreshRef.current().catch((error) => {
      if (error instanceof ApiError && error.status === 401) fail(error);
    });
    if (selectedRef.current) void loadMessagesRef.current('reconcile');
    if (uiStateRef.current.favoritesOpen) setFavoritesSyncRevision((v) => v + 1);
    if (uiStateRef.current.filesOpen) setFilesSyncRevision((v) => v + 1);
    if (uiStateRef.current.settingsOpen) setSettingsSyncRevision((v) => v + 1);
    if (uiStateRef.current.devicesOpen) {
      void devicesApi
        .list(token)
        .then(setDevices)
        .catch(() => undefined);
    }
  }, [token, fail]);

  const { sseHealthy } = useSyncEvents({
    token,
    onBatch: handleSyncBatch,
    onReconnect: handleReconnect,
    onExpired,
  });

  useEffect(() => {
    let active = true;
    setListLoading(true);
    const load = () => {
      void refreshRef.current().catch((e) => {
        if (active && e instanceof ApiError && e.status === 401) fail(e);
      });
    };
    load();
    const timer = setInterval(
      () => {
        if (!document.hidden) load();
      },
      sseHealthy ? 60_000 : 5_000,
    );
    const onVisible = () => {
      if (!document.hidden) load();
    };
    document.addEventListener('visibilitychange', onVisible);
    return () => {
      active = false;
      clearInterval(timer);
      document.removeEventListener('visibilitychange', onVisible);
    };
  }, [token, query, page, sseHealthy, fail]);

  useEffect(() => {
    if (!selected) return;
    setFeedError('');
    void loadMessages('reconcile');
    const pollTimer = setInterval(
      () => {
        if (!document.hidden) void loadMessages('latest');
      },
      sseHealthy ? 60_000 : 5_000,
    );
    const reconcileTimer = setInterval(() => {
      if (!document.hidden) void loadMessages('reconcile');
    }, 300_000);
    const onVisible = () => {
      if (!document.hidden) void loadMessages('reconcile');
    };
    document.addEventListener('visibilitychange', onVisible);
    return () => {
      clearInterval(pollTimer);
      clearInterval(reconcileTimer);
      document.removeEventListener('visibilitychange', onVisible);
    };
  }, [loadMessages, sseHealthy, selected?.id]);

  function openConversationDialog(kind: 'rename' | 'delete', target: Conversation) {
    setDialogTarget(target);
    setName(target.title);
    setError('');
    setDialog(kind);
  }
  function defaultConversationName() {
    const now = new Date();
    return `新建会话${String(now.getFullYear()).slice(-2)}${String(now.getMonth() + 1).padStart(2, '0')}${String(now.getDate()).padStart(2, '0')}`;
  }
  function select(c: Conversation) {
    if (selected?.id === c.id) return;
    setSelected(c);
    setMessageSearch('');
    setMessageSearchOpen(false);
    setMessageConnected(true);
    setFeedError('');
    setMessageQuery('');
    setError('');
    void conversationsApi
      .markRead(token, c.id)
      .then(() => refresh())
      .catch(() => undefined);
  }
  async function moveSearchResult(direction: -1 | 1) {
    if (!messageQuery || !searchResults.length) return;
    if (direction > 0 && searchResultIndex >= searchResults.length - 1) {
      if (feed.state.hasOlder && !feed.state.loadingOlder) {
        const previousCount = searchResults.length;
        try {
          await feed.history.loadOlder();
          const loadedCount = feed.history.state.data.items.length;
          setSearchResultIndex(Math.min(previousCount, Math.max(loadedCount - 1, 0)));
        } catch (error) {
          if (error instanceof ApiError && error.status === 401) fail(error);
        }
      } else {
        setSearchResultIndex(0);
      }
      return;
    }
    setSearchResultIndex((current) => {
      const next = current + direction;
      if (next < 0) return searchResults.length - 1;
      if (next >= searchResults.length) return 0;
      return next;
    });
  }
  async function send(e: FormEvent) {
    e.preventDefault();
    if (!selected || busy || sendLock.current) return;
    const id = selected.id,
      content = drafts[id]?.trim() ?? '';
    const files = attachments[id] ?? [];
    const draft = drafts[id] ?? '';
    const clientId = sendAttempts.current.get(id, content, files);
    if (!content && !files.length) return;
    const sendVersion = (sendVersions.current[id] ?? 0) + 1;
    sendVersions.current[id] = sendVersion;
    sendLock.current = true;
    setBusy(true);
    setError('');
    clearSendNotice(id);
    let sent: Message;
    try {
      if (files.length) {
        const controller = new AbortController();
        uploadController.current = controller;
        setUploadProgress({
          loaded: 0,
          total: files.reduce((sum, file) => sum + file.size, 0),
          percent: 0,
          bytesPerSecond: 0,
          remainingSeconds: null,
        });
        sent = await uploadAttachments(
          token,
          id,
          files,
          content,
          setUploadProgress,
          controller.signal,
          clientId,
        );
      } else sent = await conversationsApi.send(token, id, content, clientId);
    } catch (e) {
      if (e instanceof ApiError && e.status === 401) {
        fail(e);
        return;
      }
      const cancelled = e instanceof DOMException && e.name === 'AbortError';
      const reason =
        e instanceof ApiError
          ? `发送失败：${e.message}`
          : e instanceof Error && e.name === 'TimeoutError'
            ? '发送超时，内容已保留，请重试。'
            : '发送失败，内容已保留，请检查网络后重试。';
      setSendNotices((current) => ({
        ...current,
        [id]: {
          text: cancelled ? '已取消上传，内容已保留。' : reason,
          failed: !cancelled,
        },
      }));
      return;
    } finally {
      setBusy(false);
      sendLock.current = false;
      setUploadProgress(null);
      uploadController.current = null;
      if (selectedRef.current === id && window.matchMedia('(pointer: fine)').matches) {
        requestAnimationFrame(() => {
          if (
            selectedRef.current === id &&
            (document.activeElement === document.body ||
              document.activeElement?.closest('.composer'))
          )
            messageInput.current?.focus({ preventScroll: true });
        });
      }
    }
    sendAttempts.current.clear(id);
    setAttachments((current) => ({
      ...current,
      [id]: (current[id] ?? []).filter((file) => !files.includes(file)),
    }));
    setDrafts((d) => (d[id] === draft ? { ...d, [id]: '' } : d));
    const targetHistory = feed.getHistory(id);
    targetHistory.sent(sent);
    if (selectedRef.current === id) {
      feed.followLatest(id);
      setMessageSearch('');
      setMessageQuery('');
      setScrollRequest((value) => value + 1);
      setFeedError('');
      setMessageConnected(true);
    }
    setLastSyncedAt(Date.now());
    const results = await Promise.allSettled([
      selectedRef.current === id ? targetHistory.refreshLatest() : Promise.resolve(),
      refreshRef.current(),
    ]);
    if (
      sendVersions.current[id] === sendVersion &&
      results.some((result) => result.status === 'rejected')
    ) {
      const unauthorized = results.find(
        (result) =>
          result.status === 'rejected' &&
          result.reason instanceof ApiError &&
          result.reason.status === 401,
      );
      if (unauthorized?.status === 'rejected') {
        fail(unauthorized.reason);
        return;
      }
      setSendNotices((current) => ({
        ...current,
        [id]: {
          text: '消息已发送，列表暂未更新。',
          failed: false,
        },
      }));
    }
  }
  function clearSendNotice(id: string) {
    setSendNotices((current) => {
      if (!current[id]) return current;
      const next = { ...current };
      delete next[id];
      return next;
    });
  }
  function attachFiles(files: File[]) {
    if (!selected || busy || !files.length) return;
    const current = attachments[selected.id] ?? [];
    const combined = [...current, ...files];
    const error = validateAttachments(combined);
    if (error) {
      setError(error);
      return;
    }
    setError('');
    setAttachments((value) => ({ ...value, [selected.id]: combined }));
  }
  async function saveDialog(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError('');
    try {
      if (dialog === 'create') {
        const c = await conversationsApi.create(token, name);
        setSearch('');
        setPage(1);
        select(c);
      } else if (dialog === 'rename' && dialogTarget) {
        const c = await conversationsApi.rename(token, dialogTarget.id, name);
        setSelected((current) => (current?.id === c.id ? c : current));
      } else if (dialog === 'delete' && dialogTarget) {
        await conversationsApi.remove(token, dialogTarget.id);
        sendAttempts.current.clear(dialogTarget.id);
        clearSendNotice(dialogTarget.id);
        setAttachments((current) => {
          const next = { ...current };
          delete next[dialogTarget.id];
          return next;
        });
        setDrafts((current) => {
          const next = { ...current };
          delete next[dialogTarget.id];
          return next;
        });
        setSelected((current) => (current?.id === dialogTarget.id ? null : current));
      }
      await refresh();
      setDialog(null);
    } catch (e) {
      fail(e);
    } finally {
      setBusy(false);
    }
  }
  async function openFavorite(message: Message) {
    try {
      const conversation = await conversationsApi.detail(token, message.conversationId);
      setSearch('');
      setQuery('');
      setPage(1);
      select(conversation);
      setFavoritesOpen(false);
    } catch (e) {
      fail(e);
    }
  }
  async function showDevices() {
    setDialog('devices');
    setDeviceEdit(null);
    setDeviceToRemove(null);
    setDevices([]);
    setError('');
    try {
      setDevices(await devicesApi.list(token));
    } catch (e) {
      fail(e);
    }
  }
  async function saveDevice() {
    if (!deviceEdit || !deviceName.trim() || busy) return;
    setBusy(true);
    setError('');
    try {
      const value = await devicesApi.rename(token, deviceEdit, deviceName.trim());
      setDevices((list) => list.map((item) => (item.id === value.id ? value : item)));
      setDeviceEdit(null);
    } catch (e) {
      fail(e);
    } finally {
      setBusy(false);
    }
  }
  async function removeDevice(device: Device) {
    if (busy || device.id === session.user.deviceId) return;
    setBusy(true);
    setError('');
    try {
      await devicesApi.remove(token, device.id);
      setDevices((list) => list.filter((item) => item.id !== device.id));
      setDeviceToRemove(null);
    } catch (e) {
      fail(e);
    } finally {
      setBusy(false);
    }
  }
  async function togglePin(target = selected) {
    if (!target || pinBusy) return;
    const id = target.id;
    setPinBusy(true);
    setError('');
    try {
      const value = await conversationsApi.pin(token, id, !target.isPinned);
      setSelected((current) => (current?.id === id ? value : current));
      await refresh();
    } catch (e) {
      fail(e);
    } finally {
      setPinBusy(false);
    }
  }
  async function action(work: () => Promise<unknown>, deletedMessageId?: string) {
    try {
      setError('');
      await work();
      if (deletedMessageId) {
        mediaCache.invalidateMessage(deletedMessageId);
        feed.history.removeMessage(deletedMessageId);
      }
      await loadMessages('latest');
      await refresh();
    } catch (e) {
      fail(e);
    }
  }
  async function editMessage(message: Message, content: string) {
    try {
      const updated = await messagesApi.update(token, message.id, { content });
      feed.history.updateMessage(updated);
      try {
        await refresh();
      } catch (e) {
        if (e instanceof ApiError && e.status === 401) throw e;
        setError('消息已编辑，列表暂未更新。');
      }
    } catch (e) {
      fail(e);
      throw e;
    }
  }

  const syncConnected = lastSyncOk && (!selected || messageConnected);

  return (
    <div
      className="workspace"
      style={
        viewportHeight
          ? ({
              height: viewportHeight,
              '--workspace-height': `${viewportHeight}px`,
            } as CSSProperties)
          : undefined
      }
      onKeyDown={(e) => {
        if (
          selected &&
          !settingsOpen &&
          !favoritesOpen &&
          !filesOpen &&
          !dialog &&
          !annotationTarget &&
          (e.ctrlKey || e.metaKey) &&
          e.key.toLowerCase() === 'f'
        ) {
          e.preventDefault();
          setMessageSearchOpen(true);
          messageSearchInput.current?.focus();
        }
      }}
    >
      <ConversationSidebar
        hidden={!!selected || settingsOpen}
        userName={session.user.name}
        conversations={conversations}
        selectedId={selected?.id}
        listLoading={listLoading}
        search={search}
        query={query}
        page={page}
        busy={busy}
        pinBusy={pinBusy}
        connected={syncConnected}
        lastSyncedAt={lastSyncedAt}
        onSearchChange={setSearch}
        onPageChange={setPage}
        onSelect={select}
        onCreateConversation={() => {
          setName(defaultConversationName());
          setDialog('create');
        }}
        onOpenSettings={() => setSettingsOpen(true)}
        onOpenFavorites={() => setFavoritesOpen(true)}
        onOpenFiles={() => setFilesOpen(true)}
        onTogglePin={(c) => void togglePin(c)}
        onOpenDialog={openConversationDialog}
        onRetrySync={() => {
          void refresh().catch(fail);
          void loadMessages('reconcile');
        }}
        onLogout={() => void onLogout().catch(fail)}
      />
      <main
        className={`chat-pane ${!selected || settingsOpen ? 'mobile-hidden' : ''}`}
        onDragEnter={(e) => {
          if (e.dataTransfer.types.includes('Files')) {
            e.preventDefault();
            if (!selected || busy) return;
            dragDepth.current++;
            setDragging(true);
          }
        }}
        onDragOver={(e) => {
          if (e.dataTransfer.types.includes('Files')) {
            e.preventDefault();
            e.dataTransfer.dropEffect = !selected || busy ? 'none' : 'copy';
          }
        }}
        onDragLeave={(e) => {
          e.preventDefault();
          dragDepth.current--;
          if (dragDepth.current <= 0) {
            dragDepth.current = 0;
            setDragging(false);
          }
        }}
        onDrop={(e) => {
          if (!e.dataTransfer.types.includes('Files')) return;
          e.preventDefault();
          dragDepth.current = 0;
          setDragging(false);
          if (
            Array.from(e.dataTransfer.items).some((item) => item.webkitGetAsEntry?.()?.isDirectory)
          ) {
            setError('请选择文件，不能添加文件夹。');
          } else {
            attachFiles(Array.from(e.dataTransfer.files));
          }
        }}
      >
        {selected ? (
          <>
            <header className="chat-header">
              <button
                aria-label="返回会话列表"
                className="icon-btn mobile-back"
                onClick={() => setSelected(null)}
              >
                <ArrowLeft size={20} />
              </button>
              <div className="chat-title-group">
                <h2>{selected.title}</h2>
                <button
                  className="icon-btn"
                  aria-label="重命名会话"
                  title="重命名"
                  onClick={() => {
                    openConversationDialog('rename', selected);
                  }}
                >
                  <Pencil size={18} />
                </button>
              </div>
              <button
                className="icon-btn chat-search-toggle"
                aria-label={messageSearchOpen ? '收起会话搜索' : '展开会话搜索'}
                aria-expanded={messageSearchOpen}
                onClick={() => {
                  if (messageSearchOpen) {
                    setMessageSearch('');
                    setMessageQuery('');
                  }
                  setMessageSearchOpen((value) => !value);
                }}
              >
                <Search size={18} />
              </button>
              <ActionMenu
                label="更多会话操作"
                disabled={busy}
                actions={[
                  {
                    label: selected.isPinned ? '取消置顶会话' : '置顶会话',
                    icon: <Pin size={15} />,
                    disabled: pinBusy,
                    onSelect: () => void togglePin(),
                  },
                  {
                    label: '删除会话',
                    icon: <Trash2 size={15} />,
                    onSelect: () => openConversationDialog('delete', selected),
                    danger: true,
                    opensDialog: true,
                  },
                ]}
              />
            </header>
            {(!lastSyncOk || !messageConnected) && (
              <div className="chat-connection-state" role="status">
                连接中断，已有内容仍可查看。
                <button
                  onClick={() => {
                    void refresh().catch(fail);
                    void loadMessages('reconcile');
                  }}
                >
                  刷新
                </button>
              </div>
            )}
            <div className={`chat-search ${messageSearchOpen ? 'search-expanded' : ''}`}>
              <label className="search-box">
                <Search size={16} />
                <input
                  ref={messageSearchInput}
                  aria-label="搜索当前会话"
                  placeholder="搜索消息、批注或文件名…"
                  value={messageSearch}
                  onChange={(e) => setMessageSearch(e.target.value)}
                  onKeyDown={(e) => {
                    if (e.key === 'Escape') {
                      setMessageSearchOpen(false);
                      setMessageSearch('');
                      setMessageQuery('');
                      messageInput.current?.focus();
                    }
                  }}
                />
              </label>
              {messageSearch && (
                <button
                  className="icon-btn"
                  aria-label="清空会话搜索"
                  onClick={() => {
                    setMessageSearch('');
                    setMessageQuery('');
                  }}
                >
                  <X size={16} />
                </button>
              )}
              <span>
                {messages.total} {messageQuery ? '条结果' : '条消息'}
              </span>
              {messageQuery && messages.total > 0 && (
                <div className="search-result-nav" aria-label="搜索结果导航">
                  <span title={feed.state.hasOlder ? '继续点击可加载更早结果' : undefined}>
                    {searchResultIndex + 1} / {messages.total}
                  </span>
                  <button
                    className="icon-btn"
                    aria-label="上一个搜索结果"
                    title="上一个结果"
                    onClick={() => void moveSearchResult(-1)}
                  >
                    <ChevronLeft size={15} />
                  </button>
                  <button
                    className="icon-btn"
                    aria-label="下一个搜索结果"
                    title="下一个结果"
                    onClick={() => void moveSearchResult(1)}
                  >
                    <ChevronRight size={15} />
                  </button>
                </div>
              )}
            </div>
            <div className="message-feed message-feed-virtual" aria-busy={loading}>
              {!feed.state.ready || !messages.items.length ? (
                <div className="feed-empty">
                  <h3>
                    {feedError
                      ? '暂时无法加载消息'
                      : loading || !feed.state.ready
                        ? '正在加载消息…'
                        : messageQuery
                          ? '没有找到相关消息'
                          : '发送第一条消息'}
                  </h3>
                  <p>
                    {feedError
                      ? '请检查连接后重试。已有消息和草稿会保留。'
                      : loading || !feed.state.ready
                        ? '请稍候，正在获取会话内容。'
                        : messageQuery
                          ? '试试其他关键词，或清空搜索查看全部消息。'
                          : '发送文字、图片或文件，在其他设备上查看。'}
                  </p>
                  {feedError && (
                    <Button variant="outline" onClick={() => void loadMessages('reconcile')}>
                      重新加载
                    </Button>
                  )}
                </div>
              ) : (
                <VirtualMessageFeed
                  searchQuery={messageQuery}
                  focusMessageId={focusedSearchMessage}
                  onAnnotate={setAnnotationTarget}
                  currentDeviceId={session.user.deviceId}
                  key={feed.key}
                  messages={messages.items}
                  token={token}
                  memory={feed.memory}
                  hasOlder={feed.state.hasOlder}
                  loadingOlder={feed.state.loadingOlder}
                  olderError={!!feed.state.olderError}
                  onLoadOlder={() =>
                    void feed.history.loadOlder().catch((error) => {
                      if (error instanceof ApiError && error.status === 401) fail(error);
                    })
                  }
                  scrollRequest={scrollRequest}
                  onError={fail}
                  onStar={(m) =>
                    void action(() => messagesApi.update(token, m.id, { isStarred: !m.isStarred }))
                  }
                  onEdit={editMessage}
                  onDelete={(m) => void action(() => messagesApi.remove(token, m.id), m.id)}
                />
              )}
            </div>
            <MessageComposer
              dragging={dragging}
              busy={busy}
              draft={drafts[selected.id] ?? ''}
              files={attachments[selected.id] ?? []}
              notice={sendNotices[selected.id]}
              uploadProgress={uploadProgress}
              messageInput={messageInput}
              fileInput={fileInput}
              imageInput={imageInput}
              onSubmit={(e) => void send(e)}
              onDraftChange={(value) => setDrafts((d) => ({ ...d, [selected.id]: value }))}
              onAttachFiles={attachFiles}
              onRemoveFile={(file) =>
                setAttachments((current) => ({
                  ...current,
                  [selected.id]: (current[selected.id] ?? []).filter((f) => f !== file),
                }))
              }
              onClearNotice={() => clearSendNotice(selected.id)}
              onCancelUpload={() => uploadController.current?.abort()}
            />
          </>
        ) : (
          <div className="welcome-space">
            <h2>选择一个会话开始</h2>
            <p>发送文字、图片和文件，在其他设备上继续查看。</p>
            <Button
              onClick={() => {
                setName(defaultConversationName());
                setDialog('create');
              }}
            >
              <Plus size={17} />
              新建会话
            </Button>
          </div>
        )}
      </main>
      {compact && (!selected || settingsOpen) && (
        <MobileWorkspaceNav
          settings={settingsOpen}
          locked={settingsLocked}
          onChange={(value) => {
            if (settingsLocked) return;
            (document.activeElement as HTMLElement | null)?.blur();
            setSettingsOpen(value);
          }}
        />
      )}
      {error && (
        <div role="alert" className="connection-error">
          {error}
          <button aria-label="关闭提示" onClick={() => setError('')}>
            <X size={16} />
          </button>
        </div>
      )}
      {annotationTarget && (
        <AnnotationDialog
          key={annotationTarget.id}
          message={annotationTarget}
          token={token}
          onExpired={onExpired}
          onClose={() => setAnnotationTarget(null)}
          onSaved={(updated) => {
            feed.history.updateMessage(updated);
            setAnnotationRevision((value) => value + 1);
            void loadMessages('latest');
            void refresh().catch(fail);
          }}
        />
      )}
      {favoritesOpen && (
        <FavoritesPanel
          onOpenConversation={(m) => void openFavorite(m)}
          onAnnotate={setAnnotationTarget}
          annotationRevision={annotationRevision}
          sseHealthy={sseHealthy}
          syncRevision={favoritesSyncRevision}
          currentDeviceId={session.user.deviceId}
          token={token}
          onClose={() => setFavoritesOpen(false)}
          onExpired={onExpired}
        />
      )}
      {filesOpen && (
        <FilesPanel
          token={token}
          syncRevision={filesSyncRevision}
          onClose={() => setFilesOpen(false)}
          onOpenConversation={(conversationId) => {
            void conversationsApi
              .detail(token, conversationId)
              .then((conversation) => {
                setSearch('');
                setQuery('');
                setPage(1);
                select(conversation);
              })
              .catch(fail);
          }}
          onFileDeleted={(file) => {
            if (selected?.id === file.conversationId) {
              void loadMessages('latest');
            }
          }}
          onExpired={onExpired}
        />
      )}
      {settingsOpen && (
        <SettingsPanel
          embedded={compact}
          accountName={session.user.name}
          syncRevision={settingsSyncRevision}
          onLogout={onLogout}
          onNavigationLockChanged={setSettingsLocked}
          onShowDevices={() => {
            if (!compact) setSettingsOpen(false);
            void showDevices();
          }}
          deviceId={session.user.deviceId}
          onDeviceRenamed={(updated) =>
            setDevices((list) => list.map((item) => (item.id === updated.id ? updated : item)))
          }
          token={token}
          onClose={() => setSettingsOpen(false)}
          onExpired={onExpired}
          onReset={() => {
            mediaCache.clear();
            localStorage.removeItem(`syncbox-device-${session.user.id}`);
            onExpired();
          }}
        />
      )}
      {dialog === 'devices' && (
        <DevicesDialog
          devices={devices}
          currentDeviceId={session.user.deviceId}
          deviceEdit={deviceEdit}
          deviceName={deviceName}
          busy={busy}
          onRefresh={() => void showDevices()}
          onClose={() => setDialog(null)}
          onStartEdit={(d) => {
            setDeviceEdit(d.id);
            setDeviceName(d.name);
          }}
          onDeviceNameChange={setDeviceName}
          onSaveEdit={() => void saveDevice()}
          onCancelEdit={() => setDeviceEdit(null)}
          onRequestRemove={setDeviceToRemove}
        />
      )}
      {dialog && dialog !== 'devices' && (
        <div className="modal-backdrop" onClick={() => !busy && setDialog(null)}>
          <section
            role="dialog"
            aria-modal="true"
            aria-labelledby="modal-title"
            className="modal-card"
            onClick={(e) => e.stopPropagation()}
            onKeyDown={(e) => {
              if (e.key === 'Escape' && !busy) setDialog(null);
            }}
          >
            <div className="flex items-center justify-between">
              <h2 id="modal-title">
                {dialog === 'create'
                  ? '新建会话'
                  : dialog === 'rename'
                    ? '重命名会话'
                    : '删除会话？'}
              </h2>
              <button aria-label="关闭弹窗" onClick={() => setDialog(null)} disabled={busy}>
                <X size={20} />
              </button>
            </div>
            <form onSubmit={saveDialog}>
              {dialog === 'delete' ? (
                <p className="my-5 text-sm leading-6 text-muted-foreground">
                  “{dialogTarget?.title}
                  ”中的消息和附件也会一并删除，所有设备同步移除，且无法恢复。
                </p>
              ) : (
                <label className="field-label my-6">
                  会话名称
                  <input
                    autoFocus
                    value={name}
                    onChange={(e) => setName(e.target.value)}
                    placeholder="例如：临时传输、文案收藏"
                    maxLength={80}
                    required
                  />
                </label>
              )}
              <div className="flex justify-end gap-3">
                <Button
                  type="button"
                  variant="outline"
                  onClick={() => setDialog(null)}
                  disabled={busy}
                >
                  取消
                </Button>
                <Button
                  variant={dialog === 'delete' ? 'destructive' : 'default'}
                  disabled={busy || (dialog !== 'delete' && !name.trim())}
                >
                  {busy
                    ? '处理中…'
                    : dialog === 'delete'
                      ? '删除会话'
                      : dialog === 'create'
                        ? '创建会话'
                        : '保存名称'}
                </Button>
              </div>
            </form>
          </section>
        </div>
      )}
      {deviceToRemove && (
        <ConfirmDialog
          title="移除这台设备？"
          confirmLabel="移除设备"
          onCancel={() => !busy && setDeviceToRemove(null)}
          onConfirm={() => void removeDevice(deviceToRemove)}
        >
          “{deviceToRemove.name}”将从设备列表中移除，之后需要重新登录才能继续同步。
        </ConfirmDialog>
      )}
    </div>
  );
}
