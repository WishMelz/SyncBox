import { useCallback, useLayoutEffect, useMemo, useRef, useState } from 'react';
import { Virtuoso, type VirtuosoHandle } from 'react-virtuoso';
import { ArrowDown } from 'lucide-react';
import { MessageCard } from './message-card';
import { startsMessageDate, messageDateLabel } from '@/lib/message-presentation';
import type { Message } from '@/services/messages';
import type { FeedMemory } from '@/hooks/use-message-history';

interface HistoryContext {
  hasOlder: boolean;
  loadingOlder: boolean;
  olderError: boolean;
  onLoadOlder: () => void;
}
function HistoryHeader({ context }: { context?: HistoryContext }) {
  if (!context) return null;
  return (
    <div className="history-loader" role="status">
      {context.loadingOlder ? (
        '正在加载更早消息…'
      ) : context.olderError ? (
        <button onClick={context.onLoadOlder}>加载失败，点击重试</button>
      ) : context.hasOlder ? (
        '向上滚动查看更早消息'
      ) : (
        '已到最早消息'
      )}
    </div>
  );
}

export function VirtualMessageFeed({
  messages,
  token,
  currentDeviceId,
  searchQuery = '',
  memory,
  hasOlder,
  loadingOlder,
  olderError,
  onLoadOlder,
  focusMessageId,
  scrollRequest,
  onError,
  onAnnotate,
  onStar,
  onDelete,
}: {
  messages: Message[];
  token: string;
  currentDeviceId?: string | null;
  searchQuery?: string;
  memory: FeedMemory;
  hasOlder: boolean;
  loadingOlder: boolean;
  olderError: boolean;
  onLoadOlder: () => void;
  focusMessageId?: string;
  scrollRequest: number;
  onError: (e: unknown) => void;
  onAnnotate: (message: Message) => void;
  onStar: (message: Message) => void;
  onDelete: (message: Message) => void;
}) {
  const items = useMemo(() => [...messages].reverse(), [messages]);
  const dateStarts = useMemo(
    () =>
      new Set(
        items
          .filter((message, index) =>
            startsMessageDate(message.createdAt, items[index - 1]?.createdAt),
          )
          .map((message) => message.id),
      ),
    [items],
  );
  const [dataWindow, setDataWindow] = useState({ items, first: memory.first });
  // Keep surviving rows at stable virtual indexes when the current page shifts on polling.
  if (dataWindow.items !== items) {
    const removed = dataWindow.items.findIndex((m) => m.id === items[0]?.id);
    const prepended = items.findIndex((m) => m.id === dataWindow.items[0]?.id);
    const shift = removed >= 0 ? removed : prepended >= 0 ? -prepended : 0;
    setDataWindow({ items, first: dataWindow.first + shift });
  }
  const list = useRef<VirtuosoHandle>(null);
  const initialPosition = useRef({ snapshot: memory.atBottom ? undefined : memory.snapshot });
  const [atBottom, setAtBottom] = useState(memory.atBottom);
  const bottom = useRef(memory.atBottom);
  const scrollElement = useRef<HTMLElement | null>(null);
  const current = useRef({ hasOlder, loadingOlder, olderError, onLoadOlder });
  current.current = { hasOlder, loadingOlder, olderError, onLoadOlder };
  const savePosition = useCallback(() => {
    const el = scrollElement.current;
    if (!el) return;
    // Native scroll events can precede Virtuoso's own scroll-state update.
    const scrollTop =
      el.scrollTop - (el.querySelector('.history-loader')?.getBoundingClientRect().height ?? 0);
    list.current?.getState((state) => {
      memory.snapshot = { ...state, scrollTop };
    });
  }, [memory]);
  const capture = useCallback(() => {
    savePosition();
    const el = scrollElement.current,
      state = current.current;
    if (el && el.scrollTop < 120 && state.hasOlder && !state.loadingOlder && !state.olderError)
      state.onLoadOlder();
  }, [savePosition]);
  const setScroller = useCallback(
    (element: HTMLElement | Window | null) => {
      if (!element) savePosition();
      scrollElement.current?.removeEventListener('scroll', capture);
      scrollElement.current = element instanceof HTMLElement ? element : null;
      scrollElement.current?.addEventListener('scroll', capture, { passive: true });
    },
    [capture, savePosition],
  );
  useLayoutEffect(() => {
    memory.first = dataWindow.first;
  }, [memory, dataWindow.first]);
  const previous = useRef({ request: scrollRequest, newest: items.at(-1)?.id });
  useLayoutEffect(() => {
    const follow =
      previous.current.request !== scrollRequest ||
      (previous.current.newest !== items.at(-1)?.id && bottom.current);
    previous.current = { request: scrollRequest, newest: items.at(-1)?.id };
    if (!follow) return;
    list.current?.scrollToIndex({ index: 'LAST', align: 'end', behavior: 'auto' });
  }, [scrollRequest, items]);
  useLayoutEffect(() => {
    if (!focusMessageId) return;
    const index = items.findIndex((message) => message.id === focusMessageId);
    if (index >= 0) list.current?.scrollToIndex({ index, align: 'center', behavior: 'smooth' });
  }, [focusMessageId, items]);
  return (
    <div className="virtual-feed-shell">
      <Virtuoso
        ref={list}
        className="virtual-message-feed"
        data={items}
        firstItemIndex={dataWindow.first}
        scrollerRef={setScroller}
        restoreStateFrom={initialPosition.current.snapshot}
        computeItemKey={(_index, item) => item.id}
        {...(!initialPosition.current.snapshot
          ? { initialTopMostItemIndex: { index: items.length - 1, align: 'end' as const } }
          : {})}
        components={{ Header: HistoryHeader }}
        context={{ hasOlder, loadingOlder, olderError, onLoadOlder }}
        defaultItemHeight={180}
        totalListHeightChanged={() =>
          requestAnimationFrame(() => {
            const el = scrollElement.current,
              state = current.current;
            if (
              el &&
              el.scrollHeight <= el.clientHeight + 1 &&
              state.hasOlder &&
              !state.loadingOlder &&
              !state.olderError
            )
              state.onLoadOlder();
          })
        }
        increaseViewportBy={{ top: 300, bottom: 300 }}
        atBottomThreshold={64}
        atBottomStateChange={(value) => {
          bottom.current = value;
          setAtBottom(value);
          memory.atBottom = value;
        }}
        followOutput={(isAtBottom) => (isAtBottom ? 'auto' : false)}
        itemContent={(_index, message) => (
          <div className="virtual-message-row" data-message-id={message.id}>
            {dateStarts.has(message.id) && (
              <div className="message-date-separator">
                <time dateTime={message.createdAt}>{messageDateLabel(message.createdAt)}</time>
              </div>
            )}
            <MessageCard
              searchQuery={searchQuery}
              showDate={false}
              message={message}
              token={token}
              currentDeviceId={currentDeviceId}
              onError={onError}
              onAnnotate={() => onAnnotate(message)}
              onStar={() => onStar(message)}
              onDelete={() => onDelete(message)}
            />
          </div>
        )}
      />
      {!atBottom && (
        <button
          className="feed-jump-bottom"
          onClick={() => list.current?.scrollToIndex({ index: 'LAST', align: 'end' })}
        >
          <ArrowDown size={14} />
          回到底部
        </button>
      )}
    </div>
  );
}
