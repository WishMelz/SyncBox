import { type FormEvent, type RefObject } from 'react';
import { Send, X } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { AttachmentDrafts } from '@/components/chat/attachment-drafts';
import { AttachmentMenu } from '@/components/chat/attachment-menu';
import { formatBytes } from '@/lib/attachments';
import type { UploadProgress } from '@/services/attachments';

export function MessageComposer({
  dragging,
  busy,
  draft,
  files,
  notice,
  uploadProgress,
  messageInput,
  fileInput,
  imageInput,
  onSubmit,
  onDraftChange,
  onAttachFiles,
  onRemoveFile,
  onClearNotice,
  onCancelUpload,
}: {
  dragging: boolean;
  busy: boolean;
  draft: string;
  files: File[];
  notice?: { text: string; failed: boolean };
  uploadProgress: UploadProgress | null;
  messageInput: RefObject<HTMLTextAreaElement | null>;
  fileInput: RefObject<HTMLInputElement | null>;
  imageInput: RefObject<HTMLInputElement | null>;
  onSubmit: (e: FormEvent) => void;
  onDraftChange: (value: string) => void;
  onAttachFiles: (files: File[]) => void;
  onRemoveFile: (file: File) => void;
  onClearNotice: () => void;
  onCancelUpload: () => void;
}) {
  return (
    <form
      className={`composer ${dragging ? 'composer-dragging' : ''}`}
      onSubmit={onSubmit}
      onPaste={(e) => {
        const pasted = Array.from(e.clipboardData.files);
        if (pasted.length) {
          e.preventDefault();
          onAttachFiles(pasted);
        }
      }}
    >
      {notice && (
        <section
          className={`composer-notice ${notice.failed ? 'composer-notice-error' : ''}`}
          role={notice.failed ? 'alert' : 'status'}
        >
          <p>{notice.text}</p>
          <button type="button" aria-label="关闭发送提示" onClick={onClearNotice}>
            <X size={14} />
          </button>
        </section>
      )}
      {dragging && <p className="attachment-drop-hint">松开即可添加附件</p>}
      <AttachmentDrafts files={files} disabled={busy} remove={onRemoveFile} />
      <input
        ref={fileInput}
        type="file"
        multiple
        hidden
        aria-label="选择附件文件"
        onChange={(e) => {
          onAttachFiles(Array.from(e.target.files ?? []));
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
          onAttachFiles(Array.from(e.target.files ?? []));
          e.target.value = '';
        }}
      />
      <div className="composer-entry">
        <AttachmentMenu
          disabled={busy || files.length >= 5}
          onFiles={() => fileInput.current?.click()}
          onImages={() => imageInput.current?.click()}
        />
        <textarea
          ref={messageInput}
          aria-label="消息内容"
          placeholder="输入消息…"
          rows={1}
          maxLength={50000}
          value={draft}
          disabled={busy}
          onChange={(e) => onDraftChange(e.target.value)}
          onKeyDown={(e) => {
            const desktop = window.matchMedia('(min-width: 768px) and (pointer: fine)').matches;
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
              onSubmit(e);
            }
          }}
        />
        <Button
          className="composer-send"
          aria-label={busy ? '发送中' : '发送'}
          title="发送；电脑端 Enter 发送、Shift + Enter 换行"
          disabled={busy || (!draft.trim() && !files.length)}
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
          <button type="button" className="attachment-upload-cancel" onClick={onCancelUpload}>
            取消上传
          </button>
        </section>
      )}
    </form>
  );
}
