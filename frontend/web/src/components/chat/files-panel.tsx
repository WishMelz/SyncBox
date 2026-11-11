import { useEffect, useRef, useState } from 'react';
import { FileImage, FileText, FolderOpen, Search, X } from 'lucide-react';
import { filesApi, type FileItem, type FilePage } from '@/services/files';
import { ApiError } from '@/services/api';
import { formatBytes } from '@/lib/attachments';
import { HighlightText } from '@/components/ui/highlight-text';
import { MessageImage } from './message-image';
import { MessageAttachments } from './message-attachments';
import type { Attachment } from '@/services/messages';

type FileKind = 'all' | 'image' | 'attachment';

export function FilesPanel({
  token,
  onClose,
  onOpenConversation,
  onExpired,
}: {
  token: string;
  onClose: () => void;
  onOpenConversation: (conversationId: string) => void;
  onExpired: () => void;
}) {
  const [data, setData] = useState<FilePage>({ items: [], total: 0, page: 1, pageSize: 30, totalPages: 0 });
  const [search, setSearch] = useState('');
  const [query, setQuery] = useState('');
  const [kind, setKind] = useState<FileKind>('all');
  const [page, setPage] = useState(1);
  const [refresh, setRefresh] = useState(0);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const panel = useRef<HTMLElement>(null);

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
    const controller = new AbortController();
    let active = true;
    setLoading(true);
    setError('');
    void filesApi
      .list(token, { q: query, page, ...(kind === 'all' ? {} : { kind }) }, controller.signal)
      .then((result) => {
        if (!active) return;
        if (page > 1 && !result.items.length) setPage(Math.max(1, result.totalPages));
        else setData(result);
      })
      .catch((reason: unknown) => {
        if (!active || controller.signal.aborted) return;
        if (reason instanceof ApiError && reason.status === 401) onExpired();
        else setError('文件加载失败，请重试。');
      })
      .finally(() => {
        if (active) setLoading(false);
      });
    return () => {
      active = false;
      controller.abort();
    };
  }, [token, query, page, kind, refresh, onExpired]);

  function attachment(file: FileItem): Attachment {
    return {
      id: file.id,
      name: file.name,
      mimeType: file.mimeType,
      size: file.size,
      hasPreview: file.hasPreview,
      deletedAt: null,
      width: file.width,
      height: file.height,
    };
  }

  return (
    <div className="favorites-backdrop" onClick={onClose}>
      <section
        ref={panel}
        tabIndex={-1}
        className="favorites-panel files-panel"
        role="dialog"
        aria-modal="true"
        aria-labelledby="files-title"
        onClick={(event) => event.stopPropagation()}
        onKeyDown={(event) => {
          if (event.key === 'Escape') onClose();
        }}
      >
        <header className="favorites-header">
          <h2 id="files-title">
            文件 <small>{data.total}</small>
          </h2>
          <button aria-label="关闭文件" onClick={onClose}>
            <X size={21} />
          </button>
        </header>
        <div className="favorites-search files-toolbar">
          <label className="search-box">
            <Search size={16} />
            <input
              aria-label="搜索文件"
              placeholder="搜索文件名或所属会话"
              value={search}
              onChange={(event) => setSearch(event.target.value)}
            />
          </label>
          <div className="files-kind-tabs" role="tablist" aria-label="文件类型">
            {(
              [
                ['all', '全部'],
                ['image', '图片'],
                ['attachment', '附件'],
              ] as const
            ).map(([value, label]) => (
              <button
                key={value}
                role="tab"
                aria-selected={kind === value}
                className={kind === value ? 'active' : ''}
                onClick={() => {
                  setKind(value);
                  setPage(1);
                }}
              >
                {label}
              </button>
            ))}
          </div>
        </div>
        <div className="favorites-content files-content" aria-busy={loading}>
          {error && (
            <div role="alert" className="favorites-error">
              {error}
              <button onClick={() => setRefresh((value) => value + 1)}>重试</button>
            </div>
          )}
          {loading ? (
            <p className="favorites-empty">正在加载文件…</p>
          ) : !data.items.length ? (
            <div className="favorites-empty">
              <FolderOpen size={26} />
              <h3>{query ? '没有匹配的文件' : '暂无文件'}</h3>
              <p>{query ? '换个关键词试试' : '发送图片或附件后，会集中显示在这里。'}</p>
            </div>
          ) : (
            <div className="files-list">
              {data.items.map((file) => (
                <article className="file-entry" key={`${file.kind}:${file.id}`}>
                  <button
                    className="file-entry-source"
                    onClick={() => {
                      onOpenConversation(file.conversationId);
                      onClose();
                    }}
                    title="打开所属会话"
                  >
                    <span>
                      <HighlightText text={file.conversationTitle} query={query} />
                    </span>
                    <span>打开会话 →</span>
                  </button>
                  {file.kind === 'image' ? (
                    <div className="file-entry-preview">
                      <MessageImage
                        id={file.messageId}
                        token={token}
                        info={{ mimeType: file.mimeType, width: file.width ?? 1, height: file.height ?? 1, size: file.size }}
                        hideDownload
                      />
                    </div>
                  ) : (
                    <MessageAttachments
                      messageId={file.messageId}
                      files={[attachment(file)]}
                      token={token}
                      onError={(reason) => {
                        if (reason instanceof ApiError && reason.status === 401) onExpired();
                      }}
                      searchQuery={query}
                    />
                  )}
                  <div className="file-entry-meta">
                    {file.kind === 'image' ? <FileImage size={15} /> : <FileText size={15} />}
                    <span>
                      <strong title={file.name}>
                        <HighlightText text={file.name} query={query} />
                      </strong>
                      <small>{formatBytes(file.size)} · {new Date(file.createdAt).toLocaleString('zh-CN')}</small>
                    </span>
                  </div>
                </article>
              ))}
            </div>
          )}
        </div>
        {data.totalPages > 1 && (
          <div className="pagination">
            <button disabled={page === 1 || loading} onClick={() => setPage((value) => value - 1)}>
              上一页
            </button>
            <span>{page} / {data.totalPages}</span>
            <button disabled={page >= data.totalPages || loading} onClick={() => setPage((value) => value + 1)}>
              下一页
            </button>
          </div>
        )}
      </section>
    </div>
  );
}
