import { ApiError } from './api';
import type { Message } from './messages';

export interface UploadProgress {
  loaded: number;
  total: number;
  percent: number;
  bytesPerSecond: number;
  remainingSeconds: number | null;
}

export function uploadAttachments(
  token: string,
  conversationId: string,
  files: File[],
  content: string,
  progress: (progress: UploadProgress) => void,
  signal: AbortSignal,
  clientId?: string,
): Promise<Message> {
  const body = new FormData();
  // Unicode names are sent in a UTF-8 text field, independent of multipart filename encoding.
  body.append('names', JSON.stringify(files.map((f) => f.name || 'clipboard.png')));
  body.append('content', content);
  if (clientId) body.append('clientId', clientId);
  // Keep the browser filename as a fallback for older server deployments.
  for (const file of files) body.append('files', file, file.name || 'clipboard.png');
  return new Promise((resolve, reject) => {
    const xhr = new XMLHttpRequest();
    const abort = () => xhr.abort();
    const cleanup = () => signal.removeEventListener('abort', abort);
    xhr.open('POST', `/api/v1/conversations/${encodeURIComponent(conversationId)}/attachments`);
    xhr.setRequestHeader('Authorization', `Bearer ${token}`);
    xhr.setRequestHeader('Accept', 'application/json');
    xhr.timeout = 120000;
    const startedAt = performance.now();
    xhr.upload.onprogress = (event) => {
      if (event.lengthComputable) {
        const elapsed = Math.max((performance.now() - startedAt) / 1000, 0.001);
        const bytesPerSecond = event.loaded / elapsed;
        const remainingSeconds = bytesPerSecond > 0 ? (event.total - event.loaded) / bytesPerSecond : null;
        progress({
          loaded: event.loaded,
          total: event.total,
          percent: Math.round((event.loaded / event.total) * 100),
          bytesPerSecond,
          remainingSeconds,
        });
      }
    };
    xhr.onload = () => {
      cleanup();
      let data;
      try {
        data = JSON.parse(xhr.responseText);
      } catch {
        reject(new Error('暂时无法确认发送结果。请先查看消息列表，再决定是否重试。'));
        return;
      }
      if (xhr.status >= 200 && xhr.status < 300) resolve(data as Message);
      else
        reject(
          new ApiError(
            xhr.status,
            Array.isArray(data.message)
              ? data.message.join('；')
              : (data.message ?? '附件上传失败'),
          ),
        );
    };
    xhr.onerror = () => {
      cleanup();
      reject(new Error('连接中断，附件已保留。请先确认消息是否已发送，再重试。'));
    };
    xhr.ontimeout = () => {
      cleanup();
      reject(new Error('上传超时，附件已保留。请先确认消息是否已发送，再重试。'));
    };
    xhr.onabort = () => {
      cleanup();
      reject(new DOMException('上传已取消', 'AbortError'));
    };
    if (signal.aborted) {
      reject(new DOMException('上传已取消', 'AbortError'));
      return;
    }
    signal.addEventListener('abort', abort, { once: true });
    xhr.send(body);
  });
}

export async function attachmentBlob(token: string, path: string, signal: AbortSignal) {
  const response = await fetch(`/api/v1${path}`, {
    headers: { Authorization: `Bearer ${token}` },
    signal,
  });
  if (!response.ok)
    throw new ApiError(
      response.status,
      response.status === 401 ? '登录已过期，请重新登录' : '附件下载失败，请重试',
    );
  return response.blob();
}
