import { useEffect, useRef, useState } from 'react';
import { Star, X, Search } from 'lucide-react';
import { MessageCard } from './message-card';
import { HighlightText } from '@/components/ui/highlight-text';
import { messagesApi, type Message } from '@/services/messages';
import { ApiError } from '@/services/api';
export function FavoritesPanel({
  token,
  currentDeviceId,
  onAnnotate,
  annotationRevision,
  onClose,
  onOpenConversation,
  onExpired,
}: {
  token: string;
  currentDeviceId?: string | null;
  onAnnotate: (message: Message) => void;
  annotationRevision: number;
  onClose: () => void;
  onOpenConversation: (message: Message) => void;
  onExpired: () => void;
}) {
  const [data, setData] = useState<{ items: Message[]; total: number; totalPages: number }>({
    items: [],
    total: 0,
    totalPages: 0,
  });
  const [search, setSearch] = useState(''),
    [query, setQuery] = useState(''),
    [page, setPage] = useState(1),
    [refresh, setRefresh] = useState(0);
  const [loading, setLoading] = useState(true),
    [error, setError] = useState(''),
    [busy, setBusy] = useState(false);
  const panel = useRef<HTMLElement>(null);
  const expire = useRef(onExpired);
  expire.current = onExpired;
  useEffect(() => {
    const previous = document.activeElement as HTMLElement | null;
    panel.current?.focus();
    return () => previous?.focus();
  }, []);
  useEffect(() => {
    const timer = setTimeout(() => {
      setQuery(search);
      setPage(1);
    }, 300);
    return () => clearTimeout(timer);
  }, [search]);
  useEffect(() => {
    let active = true,
      pending = false;
    setLoading(true);
    setError('');
    async function load() {
      if (pending) return;
      pending = true;
      try {
        const result = await messagesApi.starred(token, query, page);
        if (active) {
          if (page > 1 && !result.items.length) setPage(Math.max(1, result.totalPages));
          else setData(result);
        }
      } catch (e) {
        if (active) {
          if (e instanceof ApiError && e.status === 401) expire.current();
          else setError('收藏加载失败，请重试。');
        }
      } finally {
        pending = false;
        if (active) setLoading(false);
      }
    }
    void load();
    const timer = setInterval(() => {
      if (!document.hidden) void load();
    }, 5000);
    return () => {
      active = false;
      clearInterval(timer);
    };
  }, [token, query, page, refresh, annotationRevision]);
  async function change(work: () => Promise<unknown>) {
    if (busy) return;
    setBusy(true);
    setError('');
    try {
      await work();
      setRefresh((v) => v + 1);
    } catch (e) {
      fail(e);
    } finally {
      setBusy(false);
    }
  }
  function fail(e: unknown) {
    if (e instanceof ApiError && e.status === 401) onExpired();
    else setError(e instanceof ApiError ? e.message : '操作失败，请重试。');
  }
  return (
    <div className="favorites-backdrop" onClick={onClose}>
      <section
        ref={panel}
        tabIndex={-1}
        className="favorites-panel"
        role="dialog"
        aria-modal="true"
        aria-labelledby="favorites-title"
        onClick={(e) => e.stopPropagation()}
        onKeyDown={(e) => {
          if (e.key === 'Escape') onClose();
          if (e.key === 'Tab') {
            const nodes = [
              ...(panel.current?.querySelectorAll<HTMLElement>(
                'button:not(:disabled),input:not(:disabled),a[href]',
              ) ?? []),
            ];
            const first = nodes[0],
              last = nodes[nodes.length - 1];
            if (
              e.shiftKey &&
              (document.activeElement === first || document.activeElement === panel.current)
            ) {
              e.preventDefault();
              last?.focus();
            } else if (!e.shiftKey && document.activeElement === last) {
              e.preventDefault();
              first?.focus();
            }
          }
        }}
      >
        <header className="favorites-header">
          <h2 id="favorites-title">
            已收藏 <small>{data.total}</small>
          </h2>
          <button aria-label="关闭收藏" onClick={onClose}>
            <X size={21} />
          </button>
        </header>
        <div className="favorites-search">
          <label className="search-box">
            <Search size={16} />
            <input
              aria-label="搜索收藏"
              placeholder="搜索内容、批注或文件名"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
            />
          </label>
        </div>
        <div className="favorites-content" aria-busy={loading}>
          {error && (
            <div role="alert" className="favorites-error">
              {error}
              <button onClick={() => setRefresh((v) => v + 1)}>重试</button>
            </div>
          )}
          {loading ? (
            <p className="favorites-empty">正在加载收藏…</p>
          ) : !data.items.length ? (
            <div className="favorites-empty">
              <Star size={26} />
              <h3>{query ? '没有匹配的收藏' : '暂无收藏'}</h3>
              <p>{query ? '换个关键词试试' : '通过消息菜单收藏，方便随时查看。'}</p>
            </div>
          ) : (
            <div className="favorites-list">
              {data.items.map((m) => (
                <section key={m.id} className="favorite-entry">
                  <button
                    className="favorite-source"
                    onClick={() => onOpenConversation(m)}
                    aria-label={`打开会话：${m.conversationTitle ?? '原会话'}`}
                  >
                    <span>
                      <HighlightText text={m.conversationTitle ?? '原会话'} query={query} />
                    </span>
                    <span>打开会话 →</span>
                  </button>
                  {query && (
                    <small className="search-match-kind">
                      {m.annotation?.toLowerCase().includes(query.toLowerCase())
                        ? '批注匹配'
                        : m.attachments?.some((f) =>
                              f.name.toLowerCase().includes(query.toLowerCase()),
                            )
                          ? '文件名匹配'
                          : '内容匹配'}
                    </small>
                  )}
                  <MessageCard
                    searchQuery={query}
                    message={m}
                    token={token}
                    currentDeviceId={currentDeviceId}
                    onError={fail}
                    onAnnotate={() => onAnnotate(m)}
                    onStar={() =>
                      void change(() => messagesApi.update(token, m.id, { isStarred: false }))
                    }
                    onDelete={() => void change(() => messagesApi.remove(token, m.id))}
                  />
                </section>
              ))}
            </div>
          )}
        </div>
        {data.totalPages > 1 && (
          <div className="pagination">
            <button disabled={page === 1 || loading} onClick={() => setPage((p) => p - 1)}>
              上一页
            </button>
            <span>
              {page} / {data.totalPages}
            </span>
            <button
              disabled={page >= data.totalPages || loading}
              onClick={() => setPage((p) => p + 1)}
            >
              下一页
            </button>
          </div>
        )}
      </section>
    </div>
  );
}
