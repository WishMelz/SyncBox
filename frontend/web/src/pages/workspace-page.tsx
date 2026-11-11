import { ActionMenu } from '@/components/ui/action-menu';
import { BrandIcon } from '@/components/ui/brand-icon';
import { SyncStatus } from '@/components/layout/sync-status';
import { MobileWorkspaceNav } from '@/components/layout/mobile-workspace-nav';
import { AnnotationDialog } from '@/components/chat/annotation-dialog';
import { SettingsPanel } from '@/components/settings/settings-panel';
import { FavoritesPanel } from '@/components/chat/favorites-panel';
import { FilesPanel } from '@/components/chat/files-panel';
import { AttachmentMenu } from '@/components/chat/attachment-menu';
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
  LogOut,
  MessageSquare,
  Plus,
  Pin,
  Star,
  Search,
  Send,
  Pencil,
  Settings,
  Trash2,
  X,
  FolderOpen,
  RefreshCw,
} from 'lucide-react';
import { Button } from '@/components/ui/button';
import { HighlightText } from '@/components/ui/highlight-text';
import { AttachmentDrafts } from '@/components/chat/attachment-drafts';
import { validateAttachments } from '@/lib/attachments';
import { uploadAttachments, type UploadProgress } from '@/services/attachments';
import { formatBytes } from '@/lib/attachments';
import { VirtualMessageFeed } from '@/components/chat/virtual-message-feed';
import { ConversationContextMenu } from '@/components/chat/conversation-context-menu';
import { conversationsApi, type Conversation, type Page } from '@/services/conversations';
import { messagesApi, type Message } from '@/services/messages';
import { devicesApi, type Device } from '@/services/devices';
import type { Session } from '@/services/auth';
import { ApiError } from '@/services/api';
import { SendAttempts } from '@/lib/send-attempts';
import { useMessageHistory } from '@/hooks/use-message-history';

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
  const [feedError, setFeedError] = useState('');
  const [annotationTarget, setAnnotationTarget] = useState<Message | null>(null);
  const [annotationRevision, setAnnotationRevision] = useState(0);
  const [favoritesOpen, setFavoritesOpen] = useState(false);
  const [filesOpen, setFilesOpen] = useState(false);
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
    [busy, setBusy] = useState(false),
    [synced, setSynced] = useState(true);
  const [dialog, setDialog] = useState<'create' | 'rename' | 'delete' | 'devices' | null>(null),
    [name, setName] = useState(''),
    [devices, setDevices] = useState<Device[]>([]),
    [deviceEdit, setDeviceEdit] = useState<string | null>(null),
    [deviceName, setDeviceName] = useState('');
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
  useEffect(() => {
    let active = true;
    const beat = () => {
      if (active && !document.hidden) void devicesApi.heartbeat(token).catch(() => undefined);
    };
    const onVisible = () => {
      if (!document.hidden) beat();
    };
    beat();
    const timer = window.setInterval(beat, 30_000);
    document.addEventListener('visibilitychange', onVisible);
    return () => {
      active = false;
      window.clearInterval(timer);
      document.removeEventListener('visibilitychange', onVisible);
    };
  }, [token]);
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
  const fail = useCallback(
    (e: unknown) => {
      if (e instanceof ApiError && e.status === 401) {
        onExpired();
        return;
      }
      setError(e instanceof Error ? e.message : '操作失败，请重试');
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
  useEffect(() => {
    let active = true;
    let requestController: AbortController | null = null;
    setListLoading(true);
    async function load() {
      requestController?.abort();
      const controller = new AbortController();
      requestController = controller;
      conversationListController.current?.abort();
      conversationListController.current = controller;
      const revision = ++conversationListRevision.current;
      try {
        const result = await conversationsApi.list(token, query, page, controller.signal);
        if (active && revision === conversationListRevision.current) {
          setConversations(result);
          setSelected((current) =>
            current ? (result.items.find((c) => c.id === current.id) ?? current) : current,
          );
          setSynced(true);
          setLastSyncedAt(Date.now());
        }
      } catch (e) {
        if (active && revision === conversationListRevision.current && !controller.signal.aborted) {
          setSynced(false);
          if (e instanceof ApiError && e.status === 401) fail(e);
        }
      } finally {
        if (active && revision === conversationListRevision.current) setListLoading(false);
        if (requestController === controller) requestController = null;
      }
    }
    void load();
    const timer = setInterval(() => {
      if (!document.hidden) void load();
    }, 5000);
    const onVisible = () => {
      if (!document.hidden) void load();
    };
    document.addEventListener('visibilitychange', onVisible);
    return () => {
      active = false;
      requestController?.abort();
      if (conversationListController.current === requestController)
        conversationListController.current = null;
      clearInterval(timer);
      document.removeEventListener('visibilitychange', onVisible);
    };
  }, [token, query, page]);
  const loadMessages = useCallback(async () => {
    if (!selected) return;
    const id = selected.id;
    try {
      await feed.history.refresh();
      if (selectedRef.current === id) {
        setMessageConnected(true);
        setFeedError('');
      }
    } catch (e) {
      if (selectedRef.current === id) {
        if (e instanceof ApiError && e.status === 404) setSelected(null);
        setMessageConnected(false);
        setFeedError('消息加载失败，请重试');
        if (e instanceof ApiError && e.status === 401) fail(e);
      }
    }
  }, [feed.history, selected?.id]);
  useEffect(() => {
    if (!selected) return;
    setFeedError('');
    void loadMessages();
    const timer = setInterval(() => {
      if (!document.hidden) void loadMessages();
    }, 5000);
    const onVisible = () => {
      if (!document.hidden) void loadMessages();
    };
    document.addEventListener('visibilitychange', onVisible);
    return () => {
      clearInterval(timer);
      document.removeEventListener('visibilitychange', onVisible);
    };
  }, [loadMessages]);
  async function refresh() {
    conversationListController.current?.abort();
    const controller = new AbortController();
    conversationListController.current = controller;
    const revision = ++conversationListRevision.current;
    try {
      const result = await conversationsApi.list(token, query, page, controller.signal);
      if (controller.signal.aborted || revision !== conversationListRevision.current) return;
      setConversations(result);
      setSynced(true);
      setLastSyncedAt(Date.now());
    } catch (e) {
      if (controller.signal.aborted || revision !== conversationListRevision.current) return;
      setSynced(false);
      throw e;
    } finally {
      if (conversationListController.current === controller)
        conversationListController.current = null;
      if (revision === conversationListRevision.current) setListLoading(false);
    }
  }
  const refreshRef = useRef(refresh);
  refreshRef.current = refresh;
  const loadMessagesRef = useRef(loadMessages);
  loadMessagesRef.current = loadMessages;
  useEffect(() => {
    // Read SSE with fetch so the bearer token stays in the Authorization header
    // instead of appearing in proxy, browser, or server access logs.
    let stopped = false;
    let retryTimer: number | undefined;
    const controller = new AbortController();
    const refreshList = () =>
      void refreshRef.current().catch((error) => {
        if (error instanceof ApiError && error.status === 401) fail(error);
      });
    const onSync = (data: string) => {
      try {
        const detail = JSON.parse(data) as {
          scope?: string;
          conversationId?: string;
        };
        setSynced(true);
        setLastSyncedAt(Date.now());
        if (detail.scope === 'conversations' || detail.scope === 'devices') refreshList();
        if (
          detail.scope === 'messages' ||
          detail.scope === 'favorites' ||
          (detail.scope === 'conversations' && detail.conversationId === selectedRef.current)
        ) {
          void loadMessagesRef.current();
        }
      } catch {
        refreshList();
      }
    };
    const connect = async () => {
      try {
        const response = await fetch('/api/v1/events', {
          headers: { Accept: 'text/event-stream', Authorization: `Bearer ${token}` },
          signal: controller.signal,
        });
        if (!response.ok || !response.body) throw new Error('event stream unavailable');
        setSynced(true);
        const reader = response.body.getReader();
        const decoder = new TextDecoder();
        let buffer = '';
        while (!stopped) {
          const chunk = await reader.read();
          if (chunk.done) throw new Error('event stream closed');
          buffer += decoder.decode(chunk.value, { stream: true });
          const frames = buffer.split('\n\n');
          buffer = frames.pop() ?? '';
          for (const frame of frames) {
            const event = frame.match(/^event:\s*sync\ndata:\s*(.+)$/m);
            if (event?.[1]) onSync(event[1]);
          }
        }
      } catch {
        if (!stopped) {
          setSynced(false);
          retryTimer = window.setTimeout(() => void connect(), 3000);
        }
      }
    };
    void connect();
    return () => {
      stopped = true;
      controller.abort();
      if (retryTimer !== undefined) window.clearTimeout(retryTimer);
    };
  }, [token]);
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
    // Clicking the active row again should be idempotent. In particular, do not
    // clear a loaded history page while the existing selection is unchanged.
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
    // A successful write stays successful even if the following reads fail.
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
    // Refresh through the normal path so current search/selection revisions win.
    const results = await Promise.allSettled([
      selectedRef.current === id ? targetHistory.refresh() : Promise.resolve(),
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
  async function action(work: () => Promise<unknown>) {
    try {
      setError('');
      await work();
      await loadMessages();
      await refresh();
    } catch (e) {
      fail(e);
    }
  }
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
      <aside className={`conversation-pane ${selected || settingsOpen ? 'mobile-hidden' : ''}`}>
        <div className="workspace-brand">
          <div className="brand desktop-brand">
            <BrandIcon size={28} />
            SyncBox
          </div>
          <h1 className="mobile-list-title">消息列表</h1>
          <div className="workspace-header-actions">
            <button
              className="icon-btn desktop-settings-entry"
              aria-label="打开设置"
              title="设置"
              onClick={() => setSettingsOpen(true)}
            >
              <Settings size={19} />
            </button>
            <Button
              variant="ghost"
              size="icon"
              className="sidebar-create"
              aria-label="创建会话"
              title="新建会话"
              onClick={() => {
                setName(defaultConversationName());
                setDialog('create');
              }}
            >
              <Plus size={22} />
            </Button>
          </div>
        </div>
        <div className="sidebar-search-row">
          <label className="search-box">
            <Search size={16} />
            <input
              aria-label="搜索会话、消息、批注或文件名"
              placeholder="搜索"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
            />
          </label>
        </div>
        <div className="sidebar-intro">
          <h2>会话</h2>
          <div className="sidebar-actions">
            <button
              className="favorites-entry"
              aria-label="查看收藏"
              onClick={() => setFavoritesOpen(true)}
            >
              <Star size={14} />
              收藏
            </button>
            <button
              className="favorites-entry"
              aria-label="查看文件"
              onClick={() => setFilesOpen(true)}
            >
              <FolderOpen size={14} />
              文件
            </button>
          </div>
        </div>
        <div className="conversation-list" aria-busy={listLoading}>
          {listLoading && (
            <p className="list-loading" role="status">
              正在加载会话…
            </p>
          )}
          {!listLoading &&
            conversations.items.map((c) => (
              <ConversationContextMenu
                key={c.id}
                conversation={c}
                disabled={busy || pinBusy}
                onPin={() => void togglePin(c)}
                onRename={() => openConversationDialog('rename', c)}
                onDelete={() => openConversationDialog('delete', c)}
              >
                <div
                  className={`conversation-row-shell ${selected?.id === c.id ? 'selected' : ''} ${c.isPinned ? 'pinned' : ''}`}
                >
                  <button
                    onClick={() => select(c)}
                    className={`conversation-row ${selected?.id === c.id ? 'active' : ''}`}
                  >
                    <span className="conversation-text">
                      <span className="conversation-title">
                        {c.isPinned && (
                          <span className="conversation-pin" title="已置顶">
                            <Pin size={12} fill="currentColor" />
                          </span>
                        )}
                        <span className="conversation-name">
                          <HighlightText text={c.title} query={query} />
                        </span>
                        <time>
                          {new Date(c.updatedAt).toLocaleDateString('zh-CN', {
                            month: 'numeric',
                            day: 'numeric',
                          })}
                        </time>
                      </span>
                      <span className="preview">
                        {c.preview ? <HighlightText text={c.preview} query={query} /> : '尚无消息'}
                      </span>
                    </span>
                  </button>
                  <ActionMenu
                    label={`会话操作：${c.title}`}
                    disabled={busy || pinBusy}
                    actions={[
                      {
                        label: c.isPinned ? '取消置顶' : '置顶',
                        icon: <Pin size={15} />,
                        onSelect: () => void togglePin(c),
                      },
                      {
                        label: '改名',
                        icon: <Pencil size={15} />,
                        onSelect: () => openConversationDialog('rename', c),
                        opensDialog: true,
                      },
                      {
                        label: '删除',
                        icon: <Trash2 size={15} />,
                        onSelect: () => openConversationDialog('delete', c),
                        danger: true,
                        opensDialog: true,
                      },
                    ]}
                  />
                </div>
              </ConversationContextMenu>
            ))}
          {!listLoading && !conversations.items.length && (
            <div className="list-empty">
              <MessageSquare size={28} />
              <p>{!synced ? '暂时无法连接服务' : query ? '没有找到相关会话' : '还没有会话'}</p>
              <small>
                {query ? '试试消息内容、批注或文件名' : '新建一个会话，在手机和电脑之间共享内容'}
              </small>
              {!synced && <button onClick={() => void refresh().catch(fail)}>重新连接</button>}
            </div>
          )}
        </div>
        {conversations.totalPages > 1 && (
          <div className="pagination">
            <button
              disabled={page === 1}
              onClick={() => setPage((p) => p - 1)}
              aria-label="上一页会话"
            >
              <ChevronLeft size={16} />
            </button>
            {page} / {conversations.totalPages}
            <button
              disabled={page >= conversations.totalPages}
              onClick={() => setPage((p) => p + 1)}
              aria-label="下一页会话"
            >
              <ChevronRight size={16} />
            </button>
          </div>
        )}
        <div className="profile">
          <div className="profile-name">
            <strong>{session.user.name}</strong>
            <SyncStatus
              connected={synced && (!selected || messageConnected)}
              lastSyncedAt={lastSyncedAt}
              onRetry={() => {
                void refresh().catch(fail);
                void loadMessages();
              }}
            />
          </div>
          <button
            className="icon-btn"
            aria-label="退出登录"
            onClick={() => void onLogout().catch(fail)}
          >
            <LogOut size={17} />
          </button>
        </div>
      </aside>
      <main className={`chat-pane ${!selected || settingsOpen ? 'mobile-hidden' : ''}`}>
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
            {(!synced || !messageConnected) && (
              <div className="chat-connection-state" role="status">
                连接中断，已有内容仍可查看。
                <button
                  onClick={() => {
                    void refresh().catch(fail);
                    void loadMessages();
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
                    <Button variant="outline" onClick={() => void loadMessages()}>
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
                  onDelete={(m) => void action(() => messagesApi.remove(token, m.id))}
                />
              )}
            </div>
            <form
              className={`composer ${dragging ? 'composer-dragging' : ''}`}
              onSubmit={send}
              onDragEnter={(e) => {
                if (e.dataTransfer.types.includes('Files')) {
                  e.preventDefault();
                  dragDepth.current++;
                  setDragging(true);
                }
              }}
              onDragOver={(e) => {
                if (e.dataTransfer.types.includes('Files')) {
                  e.preventDefault();
                  e.dataTransfer.dropEffect = busy ? 'none' : 'copy';
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
                e.preventDefault();
                dragDepth.current = 0;
                setDragging(false);
                attachFiles(Array.from(e.dataTransfer.files));
              }}
              onPaste={(e) => {
                const files = Array.from(e.clipboardData.files);
                if (files.length) {
                  e.preventDefault();
                  attachFiles(files);
                }
              }}
            >
              {sendNotices[selected.id] && (
                <section
                  className={`composer-notice ${sendNotices[selected.id].failed ? 'composer-notice-error' : ''}`}
                  role={sendNotices[selected.id].failed ? 'alert' : 'status'}
                >
                  <p>{sendNotices[selected.id].text}</p>
                  <button
                    type="button"
                    aria-label="关闭发送提示"
                    onClick={() => clearSendNotice(selected.id)}
                  >
                    <X size={14} />
                  </button>
                </section>
              )}
              {dragging && <p className="attachment-drop-hint">松开即可添加附件</p>}
              <AttachmentDrafts
                files={attachments[selected.id] ?? []}
                disabled={busy}
                remove={(file) =>
                  setAttachments((current) => ({
                    ...current,
                    [selected.id]: (current[selected.id] ?? []).filter((f) => f !== file),
                  }))
                }
              />
              <input
                ref={fileInput}
                type="file"
                multiple
                hidden
                aria-label="选择附件文件"
                onChange={(e) => {
                  attachFiles(Array.from(e.target.files ?? []));
                  e.target.value = '';
                }}
              />
              <input
                ref={imageInput}
                type="file"
                accept="image/*"
                multiple
                hidden
                aria-label="选择图片文件"
                onChange={(e) => {
                  attachFiles(Array.from(e.target.files ?? []));
                  e.target.value = '';
                }}
              />
              <div className="composer-entry">
                <AttachmentMenu
                  disabled={busy || (attachments[selected.id]?.length ?? 0) >= 5}
                  onFiles={() => fileInput.current?.click()}
                  onImages={() => imageInput.current?.click()}
                />
                <textarea
                  ref={messageInput}
                  aria-label="消息内容"
                  placeholder="输入消息…"
                  rows={1}
                  maxLength={50000}
                  value={drafts[selected.id] ?? ''}
                  disabled={busy}
                  onChange={(e) => {
                    setDrafts((d) => ({ ...d, [selected.id]: e.target.value }));
                  }}
                  onKeyDown={(e) => {
                    const desktop = window.matchMedia(
                      '(min-width: 768px) and (pointer: fine)',
                    ).matches;
                    if (
                      e.key === 'Enter' &&
                      !e.shiftKey &&
                      !e.altKey &&
                      !e.repeat &&
                      !e.nativeEvent.isComposing &&
                      e.nativeEvent.keyCode !== 229 &&
                      (desktop || e.metaKey || e.ctrlKey)
                    ) {
                      e.preventDefault();
                      void send(e);
                    }
                  }}
                />
                <Button
                  className="composer-send"
                  aria-label={busy ? '发送中' : '发送'}
                  title="发送；电脑端 Enter 发送、Shift + Enter 换行"
                  disabled={
                    busy || (!drafts[selected.id]?.trim() && !attachments[selected.id]?.length)
                  }
                  type="submit"
                >
                  <Send size={22} />
                </Button>
              </div>
              {uploadProgress !== null && (
                <section className="attachment-upload-progress" role="status" aria-live="polite">
                  <progress max={100} value={uploadProgress.percent} aria-label="附件上传进度" />
                  <span>
                    {uploadProgress.percent < 100
                      ? `上传中 ${uploadProgress.percent}% · ${formatBytes(uploadProgress.loaded)} / ${formatBytes(uploadProgress.total)} · ${formatBytes(uploadProgress.bytesPerSecond)}/秒${uploadProgress.remainingSeconds === null ? '' : ` · 还需 ${Math.max(1, Math.ceil(uploadProgress.remainingSeconds))} 秒`}`
                      : '正在保存附件…'}
                  </span>
                  <button
                    type="button"
                    className="attachment-upload-cancel"
                    onClick={() => uploadController.current?.abort()}
                  >
                    取消上传
                  </button>
                </section>
              )}
            </form>
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
            void loadMessages();
            void refresh().catch(fail);
          }}
        />
      )}
      {favoritesOpen && (
        <FavoritesPanel
          onOpenConversation={(m) => void openFavorite(m)}
          onAnnotate={setAnnotationTarget}
          annotationRevision={annotationRevision}
          currentDeviceId={session.user.deviceId}
          token={token}
          onClose={() => setFavoritesOpen(false)}
          onExpired={onExpired}
        />
      )}
      {filesOpen && (
        <FilesPanel
          token={token}
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
          onExpired={onExpired}
        />
      )}
      {settingsOpen && (
        <SettingsPanel
          embedded={compact}
          accountName={session.user.name}
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
            localStorage.removeItem(`syncbox-device-${session.user.id}`);
            onExpired();
          }}
        />
      )}
      {dialog && (
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
                    : dialog === 'delete'
                      ? '删除会话？'
                      : '我的设备'}
              </h2>
              {dialog === 'devices' && (
                <button
                  className="device-refresh-button"
                  type="button"
                  onClick={() => void showDevices()}
                  disabled={busy}
                  title="刷新设备状态"
                >
                  <RefreshCw size={15} />
                  刷新
                </button>
              )}
              <button aria-label="关闭弹窗" onClick={() => setDialog(null)} disabled={busy}>
                <X size={20} />
              </button>
            </div>
            {dialog === 'devices' ? (
              <div className="device-list">
                {devices.map((d) => (
                  <div key={d.id}>
                    <span className="device-info">
                      {deviceEdit === d.id ? (
                        <input
                          autoFocus
                          value={deviceName}
                          maxLength={80}
                          disabled={busy}
                          aria-label="设备名称"
                          onChange={(e) => setDeviceName(e.target.value)}
                          onKeyDown={(e) => {
                            if (e.key === 'Enter' && !e.nativeEvent.isComposing) {
                              e.preventDefault();
                              void saveDevice();
                            }
                          }}
                        />
                      ) : (
                        <strong>
                          {d.name}
                          {d.id === session.user.deviceId && (
                            <small className="current-device">当前设备</small>
                          )}
                          <small className="device-list-id">ID：{d.id}</small>
                        </strong>
                      )}
                      <small>
                        {d.platform} ·{' '}
                        <span className={`device-presence ${d.online ? 'online' : 'offline'}`}>
                          <i aria-hidden="true" />
                          {d.online ? '在线' : '离线'}
                        </span>{' '}
                        · 最近活动 {new Date(d.lastSeenAt).toLocaleString('zh-CN')}
                      </small>
                    </span>
                    {d.id === session.user.deviceId &&
                      (deviceEdit === d.id ? (
                        <>
                          <button
                            className="device-edit-button"
                            disabled={busy || !deviceName.trim()}
                            onClick={() => void saveDevice()}
                          >
                            {busy ? '保存中…' : '保存'}
                          </button>
                          <button
                            className="device-edit-button"
                            disabled={busy}
                            onClick={() => setDeviceEdit(null)}
                          >
                            取消
                          </button>
                        </>
                      ) : (
                        <button
                          className="device-edit-button"
                          onClick={() => {
                            setDeviceEdit(d.id);
                            setDeviceName(d.name);
                          }}
                        >
                          改名
                        </button>
                      ))}
                  </div>
                ))}
              </div>
            ) : (
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
            )}
          </section>
        </div>
      )}
    </div>
  );
}
