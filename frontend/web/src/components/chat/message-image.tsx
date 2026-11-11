import { useEffect, useState } from 'react';
import { Download, X } from 'lucide-react';
import type { Message } from '@/services/messages';

export function MessageImage({
  id,
  token,
  info,
  previewPath,
  hideDownload = false,
  thumbnail = false,
  alt = '消息图片',
  onOpen,
}: {
  id: string;
  token: string;
  info: NonNullable<Message['image']>;
  previewPath?: string;
  hideDownload?: boolean;
  thumbnail?: boolean;
  alt?: string;
  onOpen?: () => void;
}) {
  const [url, setUrl] = useState('');
  const [error, setError] = useState(false);
  const [expanded, setExpanded] = useState(false);
  const [retry, setRetry] = useState(0);
  useEffect(() => {
    const abort = new AbortController();
    let objectURL = '';
    setUrl('');
    setError(false);
    void fetch(`/api/v1${previewPath ?? `/messages/${encodeURIComponent(id)}/image`}`, {
      headers: { Authorization: `Bearer ${token}` },
      signal: abort.signal,
    })
      .then(async (response) => {
        if (!response.ok) throw new Error('Image unavailable');
        const blob = await response.blob();
        if (abort.signal.aborted) return;
        objectURL = URL.createObjectURL(blob);
        setUrl(objectURL);
      })
      .catch(() => {
        if (!abort.signal.aborted) setError(true);
      });
    return () => {
      abort.abort();
      if (objectURL) URL.revokeObjectURL(objectURL);
    };
  }, [id, token, retry, previewPath]);
  useEffect(() => {
    if (!expanded) return;
    const close = (event: KeyboardEvent) => {
      if (event.key === 'Escape') setExpanded(false);
    };
    window.addEventListener('keydown', close);
    return () => window.removeEventListener('keydown', close);
  }, [expanded]);
  if (error)
    return (
      <button
        type="button"
        className={thumbnail ? 'image-thumbnail-error' : 'error-note'}
        onClick={() => setRetry((r) => r + 1)}
      >
        图片加载失败，点击重试
      </button>
    );
  if (!url)
    return (
      <p
        role="status"
        className={thumbnail ? 'image-thumbnail-loading' : 'image-loading'}
        style={
          thumbnail
            ? undefined
            : {
                aspectRatio: `${info.width}/${info.height}`,
                width: Math.min(info.width, 480),
                maxWidth: '100%',
                maxHeight: 360,
              }
        }
      >
        正在加载图片…
      </p>
    );
  return (
    <>
      <button
        type="button"
        className="message-image"
        aria-label={thumbnail ? `查看大图：${alt}` : '查看大图'}
        onClick={() => (onOpen ? onOpen() : setExpanded(true))}
      >
        <img src={url} alt={alt} width={info.width} height={info.height} />
      </button>
      {!hideDownload && (
        <a className="image-download" href={url} download={`SyncBox-${id}.webp`}>
          <Download size={15} /> 保存图片
        </a>
      )}
      {expanded && (
        <div
          className="image-lightbox"
          role="dialog"
          aria-modal="true"
          aria-label="图片预览"
          onClick={() => setExpanded(false)}
        >
          <button
            type="button"
            autoFocus
            aria-label="关闭图片预览"
            onClick={() => setExpanded(false)}
          >
            <X />
          </button>
          <img src={url} alt="消息图片大图" onClick={(e) => e.stopPropagation()} />
        </div>
      )}
    </>
  );
}
