import { apiRequest } from './api';

export interface FileItem {
  id: string;
  messageId: string;
  kind: 'image' | 'attachment';
  name: string;
  mimeType: string;
  size: number;
  hasPreview: boolean;
  width: number | null;
  height: number | null;
  conversationId: string;
  conversationTitle: string;
  createdAt: string;
}

export interface FilePage {
  items: FileItem[];
  total: number;
  page: number;
  pageSize: number;
  totalPages: number;
}

export const filesApi = {
  list: (
    token: string,
    query: {
      q?: string;
      kind?: 'image' | 'attachment';
      page?: number;
      sort?: 'newest' | 'oldest' | 'name' | 'size';
    },
    signal?: AbortSignal,
  ) => {
    const params = new URLSearchParams({
      page: String(query.page ?? 1),
      pageSize: '30',
    });
    if (query.q) params.set('q', query.q);
    if (query.kind) params.set('kind', query.kind);
    if (query.sort) params.set('sort', query.sort);
    return apiRequest<FilePage>(`/messages/files?${params}`, {
      token,
      ...(signal ? { signal } : {}),
    });
  },
  remove: (token: string, file: Pick<FileItem, 'kind' | 'id' | 'messageId'>) =>
    apiRequest<void>(
      file.kind === 'image'
        ? `/messages/${encodeURIComponent(file.messageId)}/image`
        : `/messages/${encodeURIComponent(file.messageId)}/attachments/${encodeURIComponent(file.id)}`,
      { method: 'DELETE', token },
    ),
};
