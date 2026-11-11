import { apiRequest } from './api';
import type { Message } from './messages';
export interface Conversation {
  id: string;
  title: string;
  preview?: string;
  messageCount?: number;
  unreadCount?: number;
  createdAt: string;
  updatedAt: string;
  isPinned: boolean;
}
export interface Page<T> {
  items: T[];
  total: number;
  page: number;
  totalPages: number;
  hasMore?: boolean;
  nextCursor?: string | null;
}
export const conversationsApi = {
  detail: (token: string, id: string) =>
    apiRequest<Conversation>(`/conversations/${encodeURIComponent(id)}`, { token }),
  list: (token: string, q = '', page = 1, signal?: AbortSignal) =>
    apiRequest<Page<Conversation>>(
      `/conversations?${new URLSearchParams({ q, page: String(page), pageSize: '30' })}`,
      { token, ...(signal ? { signal } : {}) },
    ),
  create: (token: string, title: string) =>
    apiRequest<Conversation>('/conversations', { token, method: 'POST', body: { title } }),
  rename: (token: string, id: string, title: string) =>
    apiRequest<Conversation>(`/conversations/${id}`, { token, method: 'PATCH', body: { title } }),
  pin: (token: string, id: string, pinned: boolean) =>
    apiRequest<Conversation>(`/conversations/${id}`, { token, method: 'PATCH', body: { pinned } }),
  remove: (token: string, id: string) =>
    apiRequest<void>(`/conversations/${id}`, { token, method: 'DELETE' }),
  markRead: (token: string, id: string) =>
    apiRequest<void>(`/conversations/${id}/read`, { token, method: 'PATCH' }),
  history: (
    token: string,
    id: string,
    q = '',
    page = 1,
    cursors: { before?: string; since?: string } = {},
  ) =>
    apiRequest<Page<Message>>(
      `/conversations/${id}/messages?${new URLSearchParams({
        q,
        page: String(page),
        pageSize: '30',
        ...(Object.fromEntries(
          Object.entries(cursors).filter(([, value]) => value !== undefined),
        ) as Record<string, string>),
      })}`,
      { token },
    ),
  sendImage: (token: string, id: string, image: File, content: string, clientId?: string) => {
    const body = new FormData();
    body.append('image', image);
    body.append('content', content);
    if (clientId) body.append('clientId', clientId);
    return apiRequest<Message>(`/conversations/${id}/images`, { token, method: 'POST', body });
  },
  send: (token: string, id: string, content: string, clientId?: string) =>
    apiRequest<Message>(`/conversations/${id}/messages`, {
      token,
      method: 'POST',
      body: { content, ...(clientId ? { clientId } : {}) },
      signal: AbortSignal.timeout(30_000),
    }),
};
