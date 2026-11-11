import { apiRequest } from './api';
export type DevicePlatform =
  'ios' | 'ipados' | 'macos' | 'web' | 'android' | 'windows' | 'linux' | 'other';
export interface Device {
  id: string;
  name: string;
  platform: DevicePlatform;
  createdAt: string;
  lastSeenAt: string;
  online?: boolean;
  fingerprintBound?: boolean;
  identityMode?: 'fingerprint' | 'installation' | 'legacy';
}
export const devicesApi = {
  register: (
    token: string,
    body: {
      id?: string;
      name: string;
      platform: DevicePlatform;
      installationId?: string;
      fingerprint?: string;
      identityMode?: 'fingerprint';
    },
  ) => apiRequest<Device>('/devices', { method: 'POST', token, body }),
  list: (token: string) => apiRequest<Device[]>('/devices', { token }),
  heartbeat: (token: string) => apiRequest<void>('/devices/heartbeat', { method: 'POST', token }),
  rename: (token: string, id: string, name: string) =>
    apiRequest<Device>(`/devices/${encodeURIComponent(id)}`, {
      method: 'PATCH',
      token,
      body: { name },
    }),
  remove: (token: string, id: string) =>
    apiRequest<void>(`/devices/${encodeURIComponent(id)}`, { method: 'DELETE', token }),
};
