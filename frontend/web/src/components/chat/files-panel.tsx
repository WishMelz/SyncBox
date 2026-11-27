import { useEffect, useRef, useState } from 'react';
import { FileImage, FileText, FolderOpen, Search, Trash2, X } from 'lucide-react';
import { filesApi, type FileItem, type FilePage } from '@/services/files';
import { ApiError } from '@/services/api';
import { formatBytes } from '@/lib/attachments';
import { HighlightText } from '@/components/ui/highlight-text';
import { ConfirmDialog } from '@/components/ui/confirm-dialog';
import { MessageImage } from './message-image';
import { MessageAttachments } from './message-attachments';
import type { Attachment } from '@/services/messages';
import { mediaCache } from '@/lib/media-cache';

type FileCategory = 'all' | 'image' | 'file';
type FileSort = 'newest' | 'oldest' | 'name' | 'size';

export function FilesPanel({
  token,
  syncRevision = 0,
  onClose,
  onOpenConversation,
  onFileDeleted,
  onExpired,
}: {
  token: string;
  syncRevision?: number;
  onClose: () => void;
  onOpenConversation: (conversationId: string) => void;
  onFileDeleted?: (file: FileItem) => void;
  onExpired: () => void;
}) {
  const [data, setData] = useState<FilePage>({
    items: [],
    total: 0,
    page: 1,
    pageSize: 30,
    totalPages: 0,
  });
  const [search, setSearch] = useState('');
  const [query, setQuery] = useState('');
  const [category, setCategory] = useState<FileCategory>('all');
  const [sort, setSort] = useState<FileSort>('newest');
  const [page, setPage] = useState(1);
  const [refresh, setRefresh] = useState(0);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [fileToDelete, setFileToDelete] = useState<FileItem | null>(null);
  const [deleting, setDeleting] = useState(false);
  const panel = useRef<HTMLElement>(null);
  const lastFilterKey = useRef('');
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
    const controller = new AbortController();
    let active = true;
    const filterKey = `${token}:${query}:${page}:${category}:${sort}:${refresh}`;
    const foreground = lastFilterKey.current !== filterKey;
    lastFilterKey.current = filterKey;
    if (foreground) setLoading(true);
    setError('');
    void filesApi
      .list(
        token,
        { q: query, page, sort, ...(category === 'all' ? {} : { category }) },
        controller.signal,
      )
      .then((result) => {
        if (!active) return;
        if (page > 1 && !result.items.length) setPage(Math.max(1, result.totalPages));
        else setData(result);
      })
      .catch((reason: unknown) => {
        if (!active || controller.signal.aborted) return;
        if (reason instanceof ApiError && reason.status === 401) expire.current();
        else setError('文件加载失败，请重试。');
      })
      .finally(() => {
        if (active && foreground) setLoading(false);
      });
    return () => {
      active = false;
      controller.abort();
    };
  }, [token, query, page, category, sort, refresh, syncRevision]);

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
  async function removeFile(file: FileItem) {
    if (deleting) return;
    setDeleting(true);
    setError('');
    try {
      await filesApi.remove(token, file);
      mediaCache.invalidatePath(
        file.kind === 'image'
          ? `/messages/${encodeURIComponent(file.messageId)}/image`
          : `/messages/${encodeURIComponent(file.messageId)}/attachments/${encodeURIComponent(file.id)}`,
      );
      onFileDeleted?.(file);
      setData((current) => ({
        ...current,
        items: current.items.filter((item) => !(item.id === file.id && item.kind === file.kind)),
        total: Math.max(0, current.total - 1),
      }));
      setFileToDelete(null);
      setRefresh((value) => value + 1);
    } catch (reason: unknown) {
      if (reason instanceof ApiError && reason.status === 401) onExpired();
      else setError(reason instanceof ApiError ? reason.message : '删除文件失败，请重试。');
    } finally {
      setDeleting(false);
    }
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
                ['file', '文件'],
              ] as const
            ).map(([value, label]) => (
              <button
                key={value}
                role="tab"
                aria-selected={category === value}
                className={category === value ? 'active' : ''}
                onClick={() => {
                  setCategory(value);
                  setPage(1);
                }}
              >
                {label}
              </button>
            ))}
          </div>
          <label className="files-sort">
            <span>排序</span>
            <select
              aria-label="文件排序"
              value={sort}
              onChange={(event) => {
                setSort(event.target.value as FileSort);
                setPage(1);
              }}
            >
              <option value="newest">最新上传</option>
              <option value="oldest">最早上传</option>
              <option value="name">文件名</option>
              <option value="size">文件大小</option>
            </select>
          </label>
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
                        info={{
                          mimeType: file.mimeType,
                          width: file.width ?? 1,
                          height: file.height ?? 1,
                          size: file.size,
                        }}
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
                    {file.category === 'image' ? <FileImage size={15} /> : <FileText size={15} />}
                    <span>
                      <strong title={file.name}>
                        <HighlightText text={file.name} query={query} />
                      </strong>
                      <small>
                        {formatBytes(file.size)} ·{' '}
                        {new Date(file.createdAt).toLocaleString('zh-CN')}
                      </small>
                    </span>
                    <button
                      type="button"
                      className="file-entry-delete"
                      aria-label={`删除 ${file.name}`}
                      title="删除文件"
                      onClick={() => setFileToDelete(file)}
                    >
                      <Trash2 size={15} />
                    </button>
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
            <span>
              {page} / {data.totalPages}
            </span>
            <button
              disabled={page >= data.totalPages || loading}
              onClick={() => setPage((value) => value + 1)}
            >
              下一页
            </button>
          </div>
        )}
      </section>
      {fileToDelete && (
        <ConfirmDialog
          title="删除这个文件？"
          confirmLabel="删除文件"
          onCancel={() => !deleting && setFileToDelete(null)}
          onConfirm={() => void removeFile(fileToDelete)}
        >
          “{fileToDelete.name}”会从这条消息和所有设备中移除，消息文字会保留。
        </ConfirmDialog>
      )}
    </div>
  );
}
