import { useEffect, useRef, useState } from 'react';
import { Download, FileText, Image as ImageIcon, LoaderCircle } from 'lucide-react';
import { MessageImage } from './message-image';
import { AttachmentGalleryViewer } from './attachment-gallery-viewer';
import { formatBytes } from '@/lib/attachments';
import { attachmentBlob } from '@/services/attachments';
import type { Attachment } from '@/services/messages';
import { HighlightText } from '@/components/ui/highlight-text';

export function MessageAttachments({
  messageId,
  files,
  token,
  onError,
  searchQuery,
}: {
  messageId: string;
  files: Attachment[];
  token: string;
  onError: (error: unknown) => void;
  searchQuery?: string;
}) {
  const [previewId, setPreviewId] = useState<string | null>(null);
  const imageFiles = files.filter(
    (file) => !file.deletedAt && file.hasPreview && file.width && file.height,
  );
  const isAlbum = imageFiles.length > 1;
  const regularFiles = isAlbum ? files.filter((file) => !imageFiles.includes(file)) : files;
  const previewIndex = imageFiles.findIndex((file) => file.id === previewId);
  return (
    <div className="message-attachments">
      {isAlbum && (
        <div
          className={`message-image-grid count-${imageFiles.length}`}
          aria-label={`${imageFiles.length} 张图片`}
        >
          {imageFiles.map((file) => (
            <AttachmentItem
              key={file.id}
              messageId={messageId}
              file={file}
              token={token}
              onError={onError}
              searchQuery={searchQuery}
              compactImage
              onPreview={() => setPreviewId(file.id)}
            />
          ))}
        </div>
      )}
      {regularFiles.map((file) => (
        <AttachmentItem
          key={file.id}
          messageId={messageId}
          file={file}
          token={token}
          onError={onError}
          searchQuery={searchQuery}
        />
      ))}
      {previewIndex >= 0 && (
        <AttachmentGalleryViewer
          messageId={messageId}
          files={imageFiles}
          token={token}
          index={previewIndex}
          onChange={(index) => setPreviewId(imageFiles[index].id)}
          onClose={() => setPreviewId(null)}
          onError={onError}
        />
      )}
    </div>
  );
}
function AttachmentItem({
  messageId,
  file,
  token,
  onError,
  searchQuery,
  compactImage = false,
  onPreview,
}: {
  messageId: string;
  file: Attachment;
  token: string;
  onError: (error: unknown) => void;
  searchQuery?: string;
  compactImage?: boolean;
  onPreview?: () => void;
}) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const pending = useRef<AbortController | null>(null);
  const downloads = useRef(new Map<string, ReturnType<typeof setTimeout>>());
  useEffect(
    () => () => {
      pending.current?.abort();
      downloads.current.forEach((timer, url) => {
        clearTimeout(timer);
        URL.revokeObjectURL(url);
      });
    },
    [],
  );
  const path = `/messages/${messageId}/attachments/${file.id}`;
  async function download() {
    if (pending.current) return;
    const controller = new AbortController();
    pending.current = controller;
    setBusy(true);
    setError('');
    try {
      const blob = await attachmentBlob(token, path, controller.signal);
      if (controller.signal.aborted) return;
      const url = URL.createObjectURL(blob);
      const link = document.createElement('a');
      link.href = url;
      link.download = file.name;
      document.body.appendChild(link);
      link.click();
      link.remove();
      downloads.current.set(
        url,
        setTimeout(() => {
          URL.revokeObjectURL(url);
          downloads.current.delete(url);
        }, 30000),
      );
    } catch (error) {
      if (!controller.signal.aborted) {
        setError('下载失败，请再次点击下载。');
        onError(error);
      }
    } finally {
      if (!controller.signal.aborted) {
        pending.current = null;
        setBusy(false);
      }
    }
  }
  if (compactImage) {
    return (
      <figure className="attachment-image-tile">
        <div className="attachment-image-frame">
          <MessageImage
            id={messageId}
            token={token}
            info={{
              mimeType: 'image/webp',
              width: file.width!,
              height: file.height!,
              size: file.size,
            }}
            previewPath={`${path}/preview`}
            hideDownload
            thumbnail
            alt={file.name}
            onOpen={onPreview}
          />
          <button
            type="button"
            className="attachment-image-download"
            onClick={() => void download()}
            disabled={busy}
            aria-label={`下载 ${file.name}`}
            title={busy ? '下载中…' : '下载原图'}
          >
            {busy ? <LoaderCircle size={15} className="spin" /> : <Download size={15} />}
          </button>
        </div>
        <figcaption>
          <strong title={file.name}>
            <HighlightText text={file.name} query={searchQuery} />
          </strong>
          <small>{formatBytes(file.size)}</small>
        </figcaption>
        {error && (
          <p role="alert" className="error-note">
            {error}
          </p>
        )}
      </figure>
    );
  }
  return (
    <section className="attachment-item">
      {!file.deletedAt && file.hasPreview && file.width && file.height ? (
        <MessageImage
          id={messageId}
          token={token}
          info={{ mimeType: 'image/webp', width: file.width, height: file.height, size: file.size }}
          previewPath={`${path}/preview`}
          hideDownload
        />
      ) : null}
      <div className="attachment-file-row">
        {file.hasPreview ? <ImageIcon size={24} /> : <FileText size={24} />}
        <div className="attachment-file-info">
          <strong title={file.name}>
            <HighlightText text={file.name} query={searchQuery} />
          </strong>
          <small>
            {file.deletedAt ? '文件已按闲置清理规则删除' : `${formatBytes(file.size)} · 原始文件`}
          </small>
        </div>
        <button
          type="button"
          className="attachment-download"
          onClick={() => void download()}
          disabled={busy || !!file.deletedAt}
          aria-label={`下载 ${file.name}`}
        >
          {busy ? <LoaderCircle size={17} className="spin" /> : <Download size={17} />}
          <span>{file.deletedAt ? '已清理' : busy ? '下载中…' : '下载'}</span>
        </button>
      </div>
      {error && (
        <p role="alert" className="error-note">
          {error}
        </p>
      )}
    </section>
  );
}
