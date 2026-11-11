import { useEffect, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
import { ChevronLeft, ChevronRight, X } from 'lucide-react';
import { attachmentBlob } from '@/services/attachments';
import { formatBytes } from '@/lib/attachments';
import type { Attachment } from '@/services/messages';

export function AttachmentGalleryViewer({
  messageId,
  files,
  token,
  index,
  onChange,
  onClose,
  onError,
}: {
  messageId: string;
  files: Attachment[];
  token: string;
  index: number;
  onChange: (index: number) => void;
  onClose: () => void;
  onError: (error: unknown) => void;
}) {
  const file = files[index];
  const dialog = useRef<HTMLDialogElement>(null);
  const [preview, setPreview] = useState({ id: '', url: '', error: false });
  const [retry, setRetry] = useState(0);
  const reportError = useRef(onError);
  reportError.current = onError;
  const touch = useRef<{ x: number; y: number } | null>(null);
  useEffect(() => {
    const before = document.activeElement as HTMLElement | null;
    const node = dialog.current!;
    node.showModal();
    return () => {
      node.close();
      if (before?.isConnected) before.focus({ preventScroll: true });
    };
  }, []);
  useEffect(() => {
    const abort = new AbortController();
    let url = '';
    setPreview({ id: file.id, url: '', error: false });
    void attachmentBlob(
      token,
      `/messages/${messageId}/attachments/${file.id}/preview`,
      abort.signal,
    )
      .then((blob) => {
        if (abort.signal.aborted) return;
        url = URL.createObjectURL(blob);
        setPreview({ id: file.id, url, error: false });
      })
      .catch((error: unknown) => {
        if (abort.signal.aborted) return;
        setPreview({ id: file.id, url: '', error: true });
        reportError.current(error);
      });
    return () => {
      abort.abort();
      if (url) URL.revokeObjectURL(url);
    };
  }, [token, messageId, file.id, retry]);
  const move = (direction: number) => {
    const next = index + direction;
    if (next >= 0 && next < files.length) onChange(next);
  };
  const current = preview.id === file.id ? preview : null;
  return createPortal(
    <dialog
      ref={dialog}
      className="attachment-gallery-viewer"
      aria-label="图片预览"
      onCancel={(event) => {
        event.preventDefault();
        onClose();
      }}
      onKeyDown={(event) => {
        event.stopPropagation();
        if (event.key === 'ArrowLeft' || event.key === 'ArrowRight') {
          event.preventDefault();
          move(event.key === 'ArrowLeft' ? -1 : 1);
        }
      }}
    >
      <header>
        <div className="gallery-file-info">
          <strong title={file.name}>{file.name}</strong>
          <span aria-live="polite">
            {index + 1} / {files.length} · {formatBytes(file.size)}
          </span>
        </div>
        <button type="button" autoFocus aria-label="关闭图片预览" onClick={onClose}>
          <X size={23} />
        </button>
      </header>
      <div
        className="gallery-stage"
        onClick={(event) => {
          if (event.target === event.currentTarget) onClose();
        }}
        onTouchStart={(event) => {
          const point = event.touches[0];
          touch.current =
            event.touches.length === 1 ? { x: point.clientX, y: point.clientY } : null;
        }}
        onTouchEnd={(event) => {
          const start = touch.current,
            end = event.changedTouches[0];
          touch.current = null;
          if (!start || !end || event.touches.length) return;
          const dx = end.clientX - start.x,
            dy = end.clientY - start.y;
          if (Math.abs(dx) >= 50 && Math.abs(dx) > Math.abs(dy) * 1.5) move(dx < 0 ? 1 : -1);
        }}
        onTouchCancel={() => {
          touch.current = null;
        }}
      >
        {current?.error ? (
          <button className="gallery-retry" onClick={() => setRetry((value) => value + 1)}>
            图片加载失败，点击重试
          </button>
        ) : current?.url ? (
          <img src={current.url} alt={file.name} draggable={false} />
        ) : (
          <p role="status">正在加载图片…</p>
        )}
      </div>
      <footer aria-label="图片切换">
        <button
          type="button"
          aria-label="上一张图片"
          disabled={index === 0}
          onClick={() => move(-1)}
        >
          <ChevronLeft size={22} />
        </button>
        <span>
          {index + 1} / {files.length}
        </span>
        <button
          type="button"
          aria-label="下一张图片"
          disabled={index === files.length - 1}
          onClick={() => move(1)}
        >
          <ChevronRight size={22} />
        </button>
      </footer>
    </dialog>,
    document.body,
  );
}
