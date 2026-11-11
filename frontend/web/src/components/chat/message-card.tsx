import { ActionMenu, type MenuAction } from '@/components/ui/action-menu';
import { ConfirmDialog } from '@/components/ui/confirm-dialog';
import { MessageAttachments } from './message-attachments';
import { MessageImage } from './message-image';
import { useEffect, useRef, useState } from 'react';
import { MessageContextMenu } from './message-context-menu';
import { copyText } from '@/lib/clipboard';
import { splitMessageLinks } from '@/lib/message-presentation';
import { HighlightText } from '@/components/ui/highlight-text';
import { findHighlightRanges, sliceHighlightRanges } from '@/lib/search-highlight';
import { Check, Copy, Star, Trash2, MessageSquareText } from 'lucide-react';
import type { Message } from '@/services/messages';
export function MessageCard({
  message,
  token,
  currentDeviceId,
  showDate = true,
  searchQuery,
  onAnnotate,
  onStar,
  onDelete,
  onError,
}: {
  message: Message;
  token: string;
  currentDeviceId?: string | null;
  showDate?: boolean;
  searchQuery?: string;
  onAnnotate: () => void;
  onStar: () => void;
  onDelete: () => void;
  onError: (error: unknown) => void;
}) {
  const [confirmDelete, setConfirmDelete] = useState(false);
  const isOwn = !!currentDeviceId && message.senderDevice?.id === currentDeviceId;
  const [expandedNote, setExpandedNote] = useState(false);
  const longNote =
    (message.annotation?.length ?? 0) > 140 || (message.annotation?.split('\n').length ?? 0) > 4;
  const annotationMatches = findHighlightRanges(message.annotation ?? '', searchQuery ?? '');
  const bodyMatches = findHighlightRanges(message.content, searchQuery ?? '');
  let linkOffset = 0;
  const linkedContent = splitMessageLinks(message.content).map((part, index) => {
    const ranges = sliceHighlightRanges(bodyMatches, linkOffset, part.text.length);
    linkOffset += part.text.length;
    const content = <HighlightText text={part.text} ranges={ranges} />;
    return part.href ? (
      <a key={index} href={part.href} target="_blank" rel="noopener noreferrer">
        {content}
      </a>
    ) : (
      <span key={index}>{content}</span>
    );
  });
  const [copied, setCopied] = useState(false),
    [error, setError] = useState('');
  const bubble = useRef<HTMLDivElement>(null);
  const copiedTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  useEffect(
    () => () => {
      if (copiedTimer.current) clearTimeout(copiedTimer.current);
    },
    [],
  );
  const focusBubble = () => bubble.current?.focus({ preventScroll: true });
  const openAnnotation = () => {
    focusBubble();
    onAnnotate();
  };
  async function copy() {
    try {
      await copyText(message.content);
      setError('');
      setCopied(true);
      if (copiedTimer.current) clearTimeout(copiedTimer.current);
      copiedTimer.current = setTimeout(() => setCopied(false), 1800);
    } catch {
      setError('复制失败，请选中文字后手动复制。');
    }
  }
  const actions: MenuAction[] = [
    {
      label: copied ? '已复制' : '复制内容',
      icon: copied ? <Check size={15} /> : <Copy size={15} />,
      onSelect: () => void copy(),
    },
    {
      label: message.isStarred ? '取消收藏' : '收藏消息',
      icon: <Star size={15} />,
      onSelect: onStar,
    },
    {
      label: message.annotation ? '编辑批注' : '添加批注',
      icon: <MessageSquareText size={15} />,
      onSelect: openAnnotation,
      opensDialog: true,
    },
    {
      label: '删除消息',
      icon: <Trash2 size={15} />,
      onSelect: () => {
        focusBubble();
        setConfirmDelete(true);
      },
      danger: true,
      opensDialog: true,
    },
  ];
  return (
    <article className={`message-card tg-message${isOwn ? ' message-card-own' : ''}`}>
      <div className="message-body-line">
        <MessageContextMenu actions={actions} restoreFocus={focusBubble}>
          <div className="message-bubble" ref={bubble} tabIndex={-1}>
            <div className="message-meta">
              <span className="message-sender">{message.senderDevice?.name ?? '未知设备'}</span>
            </div>
            {message.filesExpired && <p className="error-note">图片已按闲置清理规则删除</p>}
            {message.image && <MessageImage id={message.id} token={token} info={message.image} />}
            {!!message.attachments?.length && (
              <MessageAttachments
                messageId={message.id}
                files={message.attachments}
                token={token}
                onError={onError}
                searchQuery={searchQuery}
              />
            )}
            {(!message.attachments?.length ||
              message.content !==
                `[附件] ${message.attachments.map((file) => file.name).join('、')}`) &&
              (!message.image || message.content !== '[图片]') && (
                <p className="message-text">{linkedContent}</p>
              )}
            {message.annotation && (
              <aside className="message-annotation" aria-label="消息批注">
                <button className="annotation-label" onClick={onAnnotate} title="编辑批注">
                  <MessageSquareText size={12} />
                  批注
                </button>
                <p
                  className={
                    longNote && !expandedNote && !annotationMatches.length
                      ? 'annotation-collapsed'
                      : ''
                  }
                >
                  <HighlightText text={message.annotation} ranges={annotationMatches} />
                </p>
                {longNote && !annotationMatches.length && (
                  <button
                    className="annotation-expand"
                    onClick={() => setExpandedNote((v) => !v)}
                    aria-expanded={expandedNote}
                  >
                    {expandedNote ? '收起' : '展开批注'}
                  </button>
                )}
              </aside>
            )}
            <div className="message-footer">
              {message.isStarred && (
                <Star
                  size={11}
                  className="message-star-indicator"
                  aria-label="已收藏"
                  fill="currentColor"
                />
              )}
              <time
                dateTime={message.createdAt}
                title={new Date(message.createdAt).toLocaleString('zh-CN')}
              >
                {new Date(message.createdAt).toLocaleString('zh-CN', {
                  ...(showDate ? { month: '2-digit' as const, day: '2-digit' as const } : {}),
                  hour: '2-digit',
                  minute: '2-digit',
                  hour12: false,
                })}
              </time>
            </div>
          </div>
        </MessageContextMenu>
        <div className="message-actions">
          <ActionMenu label="更多消息操作" actions={actions} />
        </div>
      </div>
      {copied && (
        <span role="status" className="copy-notice">
          已复制
        </span>
      )}
      {confirmDelete && (
        <ConfirmDialog
          title="删除这条消息？"
          onCancel={() => setConfirmDelete(false)}
          onConfirm={() => {
            setConfirmDelete(false);
            onDelete();
          }}
        >
          消息及附件将从所有设备移除，删除后无法恢复。
        </ConfirmDialog>
      )}
      {error && (
        <p role="alert" className="error-note">
          {error}
        </p>
      )}
    </article>
  );
}
