import { apiRequest } from './api';
export interface Settings {
  cleanup: {
    enabled: boolean;
    idleDays: number;
    lastRunAt: number | null;
    lastDeletedCount: number;
  };
  twoFactorEnabled: boolean;
  recoveryCodesRemaining: number;
  storage: { fileCount: number; bytes: number };
}
export interface SecurityInput {
  password: string;
  code?: string;
}
export const settingsApi = {
  get: (token: string) => apiRequest<Settings>('/settings', { token }),
  cleanup: (token: string, enabled: boolean, idleDays: number) =>
    apiRequest<Settings>('/settings/cleanup', {
      token,
      method: 'PATCH',
      body: { enabled, idleDays },
    }),
  begin: (token: string, body: SecurityInput) =>
    apiRequest<{ secret: string; otpauthUri: string; expiresIn: number }>(
      '/settings/two-factor/setup',
      { token, method: 'POST', body },
    ),
  enable: (token: string, body: SecurityInput) =>
    apiRequest<{ recoveryCodes: string[] }>('/settings/two-factor/enable', {
      token,
      method: 'POST',
      body,
    }),
  disable: (token: string, body: SecurityInput) =>
    apiRequest<Settings>('/settings/two-factor/disable', { token, method: 'POST', body }),
  reset: (token: string, body: SecurityInput & { confirmation: string }) =>
    apiRequest<void>('/settings/data', { token, method: 'DELETE', body }),
  backup: async (token: string) => {
    const response = await fetch('/api/v1/settings/backup', {
      headers: { Accept: 'application/x-sqlite3', Authorization: `Bearer ${token}` },
    });
    if (!response.ok) throw new Error('备份下载失败，请重试。');
    const blob = await response.blob();
    const expected = response.headers.get('X-SyncBox-Backup-SHA256')?.toLowerCase();
    if (!expected) throw new Error('备份缺少完整性校验信息，未保存文件。');
    let verified = false;
    let digest = expected;
    if (globalThis.crypto?.subtle) {
      digest = Array.from(
        new Uint8Array(await globalThis.crypto.subtle.digest('SHA-256', await blob.arrayBuffer())),
      )
        .map((byte) => byte.toString(16).padStart(2, '0'))
        .join('');
      if (digest !== expected) throw new Error('备份校验失败，未保存文件。');
      verified = true;
    }
    const disposition = response.headers.get('Content-Disposition') ?? '';
    const filename = disposition.match(/filename="([^"]+)"/)?.[1];
    return {
      blob,
      filename,
      sha256: digest,
      verified,
      size: Number(response.headers.get('X-SyncBox-Backup-Size')) || blob.size,
      createdAt: response.headers.get('X-SyncBox-Backup-Created-At'),
    };
  },
};
