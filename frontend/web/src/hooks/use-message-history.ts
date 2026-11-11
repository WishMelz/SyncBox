import { useLayoutEffect, useMemo, useState } from 'react';
import { conversationsApi } from '@/services/conversations';
import { MessageHistory } from '@/lib/message-history';
import type { Message } from '@/services/messages';
import type { StateSnapshot } from 'react-virtuoso';

export interface FeedMemory {
  snapshot?: StateSnapshot;
  first: number;
  atBottom: boolean;
}

export function useMessageHistory(
  token: string,
  conversationId: string | undefined,
  query: string,
) {
  const cache = useMemo(
    () => new Map<string, { history: MessageHistory<Message>; memory: FeedMemory }>(),
    [token],
  );
  const getEntry = (id: string | undefined, search: string) => {
    const key = `${id ?? ''}:${search}`;
    let entry = cache.get(key);
    if (!entry) {
      entry = {
        history: new MessageHistory<Message>((options) =>
          conversationsApi.history(token, id!, search, 1, options),
        ),
        memory: { first: 1000000, atBottom: true },
      };
      cache.set(key, entry);
      // Keep memory bounded; reading positions are retained for the recent 20 views in this session.
      if (cache.size > 20) cache.delete(cache.keys().next().value!);
    }
    return entry;
  };
  const key = `${conversationId ?? ''}:${query}`;
  const entry = getEntry(conversationId, query);
  const history = entry.history;
  const [, render] = useState(0);
  useLayoutEffect(() => history.subscribe(() => render((value) => value + 1)), [history]);
  return {
    history,
    memory: entry.memory,
    state: history.state,
    key,
    getHistory: (id: string, search = '') => getEntry(id, search).history,
    followLatest: (id: string) => {
      const memory = getEntry(id, '').memory;
      memory.atBottom = true;
      memory.snapshot = undefined;
    },
  };
}
