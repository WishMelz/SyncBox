import { ApiError } from '../services/api.ts';

export const MEDIA_CACHE_MAX_BYTES = 50 * 1024 * 1024;

interface CacheEntry {
  key: string;
  blob: Blob;
  size: number;
  url: string | null;
  refs: number;
  evicted: boolean;
}

interface InFlightRequest {
  promise: Promise<Blob>;
  subscribers: number;
  controller: AbortController;
}

export interface MediaCacheHandle {
  url: string;
  release: () => void;
}

export interface MediaCacheOptions {
  maxBytes?: number;
  fetcher?: (token: string, path: string, signal: AbortSignal) => Promise<Blob>;
  createObjectURL?: (blob: Blob) => string;
  revokeObjectURL?: (url: string) => void;
  origin?: () => string;
}

async function defaultFetch(token: string, path: string, signal: AbortSignal): Promise<Blob> {
  const response = await fetch(`/api/v1${path}`, {
    headers: { Authorization: `Bearer ${token}` },
    signal,
  });
  if (!response.ok) {
    throw new ApiError(
      response.status,
      response.status === 401 ? '登录已过期，请重新登录' : '附件读取失败，请重试',
    );
  }
  return response.blob();
}

export class MediaCache {
  private readonly maxBytes: number;
  private readonly fetcher: (token: string, path: string, signal: AbortSignal) => Promise<Blob>;
  private readonly createObjectURL: (blob: Blob) => string;
  private readonly revokeObjectURL: (url: string) => void;
  private readonly origin: () => string;
  private readonly entries = new Map<string, CacheEntry>();
  private readonly inFlight = new Map<string, InFlightRequest>();
  private totalBytes = 0;

  constructor(options: MediaCacheOptions = {}) {
    this.maxBytes = options.maxBytes ?? MEDIA_CACHE_MAX_BYTES;
    this.fetcher = options.fetcher ?? defaultFetch;
    this.createObjectURL = options.createObjectURL ?? ((blob) => URL.createObjectURL(blob));
    this.revokeObjectURL = options.revokeObjectURL ?? ((url) => URL.revokeObjectURL(url));
    this.origin = options.origin ?? (() => globalThis.location?.origin ?? '');
  }

  get bytes(): number {
    return this.totalBytes;
  }

  get size(): number {
    return this.entries.size;
  }

  private keyFor(token: string, path: string) {
    return `${this.origin()}|${token}|${path}`;
  }

  async acquire(token: string, path: string, signal?: AbortSignal): Promise<MediaCacheHandle> {
    if (signal?.aborted) {
      throw new DOMException('Aborted', 'AbortError');
    }
    const key = this.keyFor(token, path);
    const cached = this.entries.get(key);
    if (cached) {
      this.entries.delete(key);
      this.entries.set(key, cached);
      return this.retain(cached);
    }

    const blob = await this.fetchCoalesced(key, token, path, signal);
    if (signal?.aborted) {
      throw new DOMException('Aborted', 'AbortError');
    }

    const existing = this.entries.get(key);
    if (existing) {
      this.entries.delete(key);
      this.entries.set(key, existing);
      return this.retain(existing);
    }

    if (blob.size > this.maxBytes) {
      const transientUrl = this.createObjectURL(blob);
      let released = false;
      return {
        url: transientUrl,
        release: () => {
          if (released) return;
          released = true;
          this.revokeObjectURL(transientUrl);
        },
      };
    }

    const entry: CacheEntry = {
      key,
      blob,
      size: blob.size,
      url: null,
      refs: 0,
      evicted: false,
    };
    this.entries.set(key, entry);
    this.totalBytes += entry.size;
    this.evictToBudget();
    return this.retain(entry);
  }

  invalidatePath(pathPrefix: string) {
    const marker = `|${pathPrefix}`;
    for (const [key, entry] of [...this.entries]) {
      const idx = key.lastIndexOf('|');
      const entryPath = idx >= 0 ? key.slice(idx + 1) : '';
      if (key.includes(marker) && entryPath.startsWith(pathPrefix)) {
        this.removeEntry(entry);
      }
    }
  }

  invalidateMessage(messageId: string) {
    this.invalidatePath(`/messages/${encodeURIComponent(messageId)}`);
    if (encodeURIComponent(messageId) !== messageId) {
      this.invalidatePath(`/messages/${messageId}`);
    }
  }

  clear() {
    for (const entry of [...this.entries.values()]) {
      this.removeEntry(entry);
    }
    for (const req of this.inFlight.values()) {
      req.controller.abort();
    }
    this.inFlight.clear();
  }

  private retain(entry: CacheEntry): MediaCacheHandle {
    if (!entry.url) {
      entry.url = this.createObjectURL(entry.blob);
    }
    entry.refs += 1;
    let released = false;
    return {
      url: entry.url,
      release: () => {
        if (released) return;
        released = true;
        entry.refs = Math.max(0, entry.refs - 1);
        if (entry.evicted && entry.refs === 0 && entry.url) {
          this.revokeObjectURL(entry.url);
          entry.url = null;
        }
      },
    };
  }

  private evictToBudget() {
    while (this.totalBytes > this.maxBytes && this.entries.size > 0) {
      const oldest = this.entries.values().next().value;
      if (!oldest) break;
      this.removeEntry(oldest);
    }
  }

  private removeEntry(entry: CacheEntry) {
    if (this.entries.delete(entry.key)) {
      this.totalBytes = Math.max(0, this.totalBytes - entry.size);
    }
    entry.evicted = true;
    if (entry.refs === 0 && entry.url) {
      this.revokeObjectURL(entry.url);
      entry.url = null;
    }
  }

  private fetchCoalesced(
    key: string,
    token: string,
    path: string,
    signal?: AbortSignal,
  ): Promise<Blob> {
    let flight = this.inFlight.get(key);
    if (!flight) {
      const controller = new AbortController();
      const promise = this.fetcher(token, path, controller.signal).finally(() => {
        if (this.inFlight.get(key) === flight) {
          this.inFlight.delete(key);
        }
      });
      flight = { promise, subscribers: 0, controller };
      this.inFlight.set(key, flight);
    }
    flight.subscribers += 1;
    const current = flight;
    return new Promise<Blob>((resolve, reject) => {
      let settled = false;
      const onAbort = () => {
        if (settled) return;
        settled = true;
        current.subscribers = Math.max(0, current.subscribers - 1);
        if (current.subscribers === 0) {
          current.controller.abort();
          if (this.inFlight.get(key) === current) {
            this.inFlight.delete(key);
          }
        }
        reject(new DOMException('Aborted', 'AbortError'));
      };
      signal?.addEventListener('abort', onAbort, { once: true });
      current.promise.then(
        (blob) => {
          signal?.removeEventListener('abort', onAbort);
          if (settled) return;
          settled = true;
          resolve(blob);
        },
        (error) => {
          signal?.removeEventListener('abort', onAbort);
          if (settled) return;
          settled = true;
          reject(error);
        },
      );
    });
  }
}

export const mediaCache = new MediaCache();
