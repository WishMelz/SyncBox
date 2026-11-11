import { useEffect, useRef, useState, type FormEvent } from 'react';
import { createPortal } from 'react-dom';
import { MessageSquareText, X } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { messagesApi, type Message } from '@/services/messages';
import { ApiError } from '@/services/api';

export function AnnotationDialog({
  message,
  token,
  onClose,
  onSaved,
  onExpired,
}: {
  message: Message;
  token: string;
  onClose: () => void;
  onSaved: (message: Message) => void;
  onExpired: () => void;
}) {
  const [text, setText] = useState(message.annotation ?? '');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [confirmDelete, setConfirmDelete] = useState(false);
  const panel = useRef<HTMLElement>(null);
  const input = useRef<HTMLTextAreaElement>(null);
  const lock = useRef(false);
  useEffect(() => {
    const previous = document.activeElement as HTMLElement | null;
    input.current?.focus();
    return () => {
      if (previous?.isConnected) previous.focus();
    };
  }, []);
  async function save(annotation: string) {
    if (lock.current) return;
    lock.current = true;
    setBusy(true);
    setError('');
    try {
      const updated = await messagesApi.update(token, message.id, { annotation });
      onSaved(updated);
      onClose();
    } catch (e) {
      if (e instanceof ApiError && e.status === 401) onExpired();
      else setError(e instanceof Error ? e.message : '保存失败，请重试');
    } finally {
      lock.current = false;
      setBusy(false);
    }
  }
  function submit(event: FormEvent) {
    event.preventDefault();
    if (text.trim()) void save(text.trim());
  }
  return createPortal(
    <div className="annotation-backdrop">
      <section
        ref={panel}
        role="dialog"
        aria-modal="true"
        aria-labelledby="annotation-title"
        className="annotation-dialog"
        onKeyDown={(e) => {
          e.stopPropagation();
          if (e.key === 'Escape' && !busy) {
            e.preventDefault();
            onClose();
          }
          if (e.key === 'Tab') {
            const nodes = [
              ...(panel.current?.querySelectorAll<HTMLElement>(
                'button:not(:disabled),textarea:not(:disabled)',
              ) ?? []),
            ];
            const first = nodes[0],
              last = nodes.at(-1);
            if (e.shiftKey && document.activeElement === first) {
              e.preventDefault();
              last?.focus();
            } else if (!e.shiftKey && document.activeElement === last) {
              e.preventDefault();
              first?.focus();
            }
          }
        }}
      >
        <header>
          <h2 id="annotation-title">
            <MessageSquareText size={17} />
            {message.annotation ? '编辑批注' : '添加批注'}
          </h2>
          <button className="icon-btn" aria-label="关闭批注" disabled={busy} onClick={onClose}>
            <X size={18} />
          </button>
        </header>
        <p className="annotation-context">{message.content}</p>
        <form onSubmit={submit}>
          <label htmlFor="annotation-text">批注</label>
          <textarea
            ref={input}
            id="annotation-text"
            value={text}
            maxLength={2000}
            disabled={busy}
            placeholder="补充用途、想法或关键词，方便以后搜索…"
            onChange={(e) => {
              setText(e.target.value);
              setConfirmDelete(false);
            }}
          />
          <div className="annotation-hint">
            <span>所有设备可见，可通过搜索找到</span>
            <span>{text.length} / 2000</span>
          </div>
          {error && (
            <p className="error-note" role="alert">
              {error}
            </p>
          )}
          {confirmDelete && (
            <p className="annotation-delete-warning" role="alert">
              删除这条批注？消息和附件会保留。
            </p>
          )}
          <footer>
            {message.annotation && (
              <Button
                type="button"
                variant="ghost"
                className="annotation-remove"
                disabled={busy}
                onClick={() => (confirmDelete ? void save('') : setConfirmDelete(true))}
              >
                {confirmDelete ? '确认删除批注' : '删除批注'}
              </Button>
            )}
            <div>
              <Button type="button" variant="outline" onClick={onClose} disabled={busy}>
                取消
              </Button>
              <Button disabled={busy || !text.trim() || text.trim() === (message.annotation ?? '')}>
                {busy ? '保存中…' : '保存批注'}
              </Button>
            </div>
          </footer>
        </form>
      </section>
    </div>,
    document.body,
  );
}
