import { apiRequest } from './api';
export interface Attachment {
  id: string;
  name: string;
  mimeType: string;
  size: number;
  hasPreview: boolean;
  deletedAt?: number | null;
  width: number | null;
  height: number | null;
}
export interface Message {
  attachments?: Attachment[];
  filesExpired?: boolean;
  id: string;
  conversationId: string;
  conversationTitle?: string;
  image?: { mimeType: string; width: number; height: number; size: number } | null;
  title: string;
  content: string;
  annotation?: string;
  source: string;
  isRead: boolean;
  isStarred: boolean;
  createdAt: string;
  updatedAt: string;
  senderDevice: { id: string | null; name: string; platform: string } | null;
}
export interface MessageList {
  items: (Omit<Message, 'content'> & { preview: string })[];
  total: number;
  page: number;
  pageSize: number;
  totalPages: number;
}
export interface MessageQuery {
  page?: number;
  pageSize?: number;
  q?: string;
  source?: string;
  isRead?: boolean;
  isStarred?: boolean;
}
export const messagesApi = {
  starred: (token: string, q: string, page: number) =>
    apiRequest<{ items: Message[]; total: number; page: number; totalPages: number }>(
      `/messages/starred?${new URLSearchParams({ q, page: String(page), pageSize: '20' })}`,
      { token },
    ),
  list: (token: string, query: MessageQuery = {}, signal?: AbortSignal) => {
    const params = new URLSearchParams();
    for (const [key, value] of Object.entries(query))
      if (value !== undefined) params.set(key, String(value));
    return apiRequest<MessageList>(`/messages?${params}`, { token, ...(signal ? { signal } : {}) });
  },
  detail: (token: string, id: string) =>
    apiRequest<Message>(`/messages/${encodeURIComponent(id)}`, { token }),
  create: (token: string, body: Pick<Message, 'title' | 'content'> & { source?: string }) =>
    apiRequest<Message>('/messages', { method: 'POST', token, body }),
  update: (
    token: string,
    id: string,
    body: Partial<Pick<Message, 'title' | 'content' | 'isRead' | 'isStarred' | 'annotation'>>,
  ) => apiRequest<Message>(`/messages/${encodeURIComponent(id)}`, { method: 'PATCH', token, body }),
  remove: (token: string, id: string) =>
    apiRequest<void>(`/messages/${encodeURIComponent(id)}`, { method: 'DELETE', token }),
};
