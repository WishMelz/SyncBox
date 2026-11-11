// A cursor identifies a position even after the message at that position is deleted.
export interface HistoryMessage {
  id: string;
  createdAt: string;
}
export interface HistoryPage<T> {
  items: T[];
  total: number;
  page: number;
  totalPages: number;
  hasMore?: boolean;
  nextCursor?: string | null;
}
export const messageCursor = (message: HistoryMessage) => `${message.createdAt}|${message.id}`;
export function mergeHistory<T extends HistoryMessage>(...groups: T[][]): T[] {
  const unique = new Map<string, T>();
  for (const group of groups) for (const message of group) unique.set(message.id, message);
  return [...unique.values()].sort(
    (a, b) => b.createdAt.localeCompare(a.createdAt) || b.id.localeCompare(a.id),
  );
}

export interface HistoryState<T> {
  data: HistoryPage<T>;
  ready: boolean;
  loading: boolean;
  loadingOlder: boolean;
  error: unknown;
  olderError: unknown;
  hasOlder: boolean;
}

export class MessageHistory<T extends HistoryMessage> {
  state: HistoryState<T> = {
    data: { items: [], total: 0, page: 1, totalPages: 0 },
    ready: false,
    loading: false,
    loadingOlder: false,
    error: null,
    olderError: null,
    hasOlder: false,
  };
  private listeners = new Set<() => void>();
  private queue: Promise<unknown> = Promise.resolve();
  private refreshing: Promise<void> | null = null;
  private epoch = 0;
  private reloadLatest = false;
  private fetchPage: (options: { before?: string; since?: string }) => Promise<HistoryPage<T>>;
  constructor(
    fetchPage: (options: { before?: string; since?: string }) => Promise<HistoryPage<T>>,
  ) {
    this.fetchPage = fetchPage;
  }
  subscribe = (listener: () => void) => {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  };
  private update(patch: Partial<HistoryState<T>>) {
    this.state = { ...this.state, ...patch };
    for (const listener of this.listeners) listener();
  }
  private enqueue(work: () => Promise<void>) {
    const task = this.queue.then(work, work);
    this.queue = task.catch(() => undefined);
    return task;
  }
  refresh(): Promise<void> {
    if (this.refreshing) return this.refreshing;
    const epoch = this.epoch;
    this.update({ loading: !this.state.ready });
    const task = this.enqueue(async () => {
      if (epoch !== this.epoch) return;
      const oldest = this.reloadLatest ? undefined : this.state.data.items.at(-1);
      const since = oldest && messageCursor(oldest);
      let page = await this.fetchPage({ since });
      let items = page.items;
      const cursors = new Set<string>();
      while (since && page.hasMore && page.nextCursor) {
        if (cursors.has(page.nextCursor)) throw new Error('历史消息加载位置未前进，请重试。');
        cursors.add(page.nextCursor);
        page = await this.fetchPage({ since, before: page.nextCursor });
        items = mergeHistory(items, page.items);
      }
      if (!items.length && page.total > 0 && since) {
        page = await this.fetchPage({});
        items = page.items;
      }
      if (epoch !== this.epoch) return;
      this.reloadLatest = false;
      this.update({
        data: { ...page, items: mergeHistory(items) },
        ready: true,
        hasOlder: page.total > items.length,
        error: null,
      });
    })
      .catch((error: unknown) => {
        if (epoch === this.epoch) this.update({ error });
        throw error;
      })
      .finally(() => {
        if (epoch === this.epoch) this.update({ loading: false });
        if (this.refreshing === task) this.refreshing = null;
      });
    this.refreshing = task;
    return task;
  }
  loadOlder(): Promise<void> {
    if (!this.state.ready || !this.state.hasOlder || this.state.loadingOlder)
      return Promise.resolve();
    const epoch = this.epoch;
    this.update({ loadingOlder: true, olderError: null });
    return this.enqueue(async () => {
      if (epoch !== this.epoch) return;
      const oldest = this.state.data.items.at(-1);
      const page = await this.fetchPage({ before: oldest && messageCursor(oldest) });
      if (epoch !== this.epoch) return;
      const items = mergeHistory(this.state.data.items, page.items);
      this.update({
        data: { ...page, items },
        hasOlder: page.hasMore ?? page.total > items.length,
      });
    })
      .catch((olderError: unknown) => {
        if (epoch === this.epoch) this.update({ olderError });
        throw olderError;
      })
      .finally(() => {
        if (epoch === this.epoch) this.update({ loadingOlder: false });
      });
  }
  updateMessage(message: T) {
    this.update({
      data: {
        ...this.state.data,
        items: this.state.data.items.map((m) => (m.id === message.id ? message : m)),
      },
    });
  }
  sent(message: T) {
    if (!this.state.ready) this.reloadLatest = true;
    this.epoch++;
    this.refreshing = null;
    const data = this.state.data;
    const items = mergeHistory(data.items, [message]);
    const total = Math.max(
      items.length,
      data.total + (data.items.some((m) => m.id === message.id) ? 0 : 1),
    );
    this.update({
      data: { ...data, items, total, totalPages: Math.ceil(total / 30) },
      ready: true,
      loading: false,
      loadingOlder: false,
      error: null,
    });
  }
}
