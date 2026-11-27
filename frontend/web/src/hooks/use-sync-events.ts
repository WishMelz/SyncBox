import { useEffect, useRef, useState } from 'react';
import {
  addSyncEventToBatch,
  createSyncBatch,
  parseSseFrames,
  type SyncBatch,
} from '@/lib/sync-events';

const HEARTBEAT_TIMEOUT_MS = 45_000;
const COALESCE_MS = 150;

export function useSyncEvents({
  token,
  onBatch,
  onReconnect,
  onExpired,
}: {
  token: string;
  onBatch: (batch: SyncBatch) => void;
  onReconnect: () => void;
  onExpired: () => void;
}) {
  const [sseHealthy, setSseHealthy] = useState(false);
  const [lastEventAt, setLastEventAt] = useState<number | null>(null);
  const handlersRef = useRef({ onBatch, onReconnect, onExpired });
  handlersRef.current = { onBatch, onReconnect, onExpired };

  useEffect(() => {
    let stopped = false;
    let retryTimer: number | undefined;
    let coalesceTimer: number | undefined;
    let activeController: AbortController | null = null;
    let pendingBatch = createSyncBatch();
    let backoffMs = 3_000;
    let hasConnectedOnce = false;

    const flushBatch = () => {
      if (coalesceTimer !== undefined) {
        window.clearTimeout(coalesceTimer);
        coalesceTimer = undefined;
      }
      if (pendingBatch.scopes.size === 0) return;
      const batch = pendingBatch;
      pendingBatch = createSyncBatch();
      handlersRef.current.onBatch(batch);
    };

    const queueEvent = (event: Parameters<typeof addSyncEventToBatch>[1]) => {
      addSyncEventToBatch(pendingBatch, event);
      if (coalesceTimer === undefined) {
        coalesceTimer = window.setTimeout(flushBatch, COALESCE_MS);
      }
    };

    const connect = async () => {
      if (stopped) return;
      const controller = new AbortController();
      activeController = controller;
      let timeoutId: number | undefined;
      const resetHeartbeatTimeout = () => {
        if (timeoutId !== undefined) window.clearTimeout(timeoutId);
        timeoutId = window.setTimeout(() => {
          controller.abort();
        }, HEARTBEAT_TIMEOUT_MS);
      };

      try {
        resetHeartbeatTimeout();
        const response = await fetch('/api/v1/events', {
          headers: { Accept: 'text/event-stream', Authorization: `Bearer ${token}` },
          signal: controller.signal,
        });
        if (response.status === 401) {
          setSseHealthy(false);
          handlersRef.current.onExpired();
          return;
        }
        if (!response.ok || !response.body) {
          throw new Error('event stream unavailable');
        }
        setSseHealthy(true);
        setLastEventAt(Date.now());
        backoffMs = 3_000;
        const isReconnect = hasConnectedOnce;
        hasConnectedOnce = true;
        if (isReconnect) {
          handlersRef.current.onReconnect();
        }
        const reader = response.body.getReader();
        const decoder = new TextDecoder();
        let buffer = '';
        while (!stopped) {
          resetHeartbeatTimeout();
          const chunk = await reader.read();
          if (chunk.done) throw new Error('event stream closed');
          setLastEventAt(Date.now());
          buffer += decoder.decode(chunk.value, { stream: true });
          const parsed = parseSseFrames(buffer);
          buffer = parsed.rest;
          for (const event of parsed.events) {
            queueEvent(event);
          }
        }
      } catch {
        if (!stopped) {
          setSseHealthy(false);
          const delay = backoffMs;
          backoffMs = Math.min(backoffMs * 2, 30_000);
          retryTimer = window.setTimeout(() => void connect(), delay);
        }
      } finally {
        if (timeoutId !== undefined) window.clearTimeout(timeoutId);
        if (activeController === controller) activeController = null;
      }
    };

    void connect();
    return () => {
      stopped = true;
      activeController?.abort();
      if (retryTimer !== undefined) window.clearTimeout(retryTimer);
      if (coalesceTimer !== undefined) window.clearTimeout(coalesceTimer);
    };
  }, [token]);

  return { sseHealthy, lastEventAt };
}
