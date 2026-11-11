import { apiRequest } from './api';
export interface User {
  id: string;
  username: string;
  name: string;
  createdAt: string;
  deviceId?: string | null;
}
export interface Session {
  accessToken: string;
  tokenType: 'Bearer';
  expiresIn: number;
  user: User;
}
export const authApi = {
  status: () => apiRequest<{ initialized: boolean }>('/auth/status'),
  setup: (username: string, password: string) =>
    apiRequest<Session>('/auth/setup', { method: 'POST', body: { username, password } }),
  login: (username: string, password: string, code?: string) =>
    apiRequest<Session>('/auth/login', {
      method: 'POST',
      body: { username, password, ...(code ? { code } : {}) },
    }),
  me: (token: string) => apiRequest<User>('/auth/me', { token }),
  logout: (token: string) => apiRequest<void>('/auth/logout', { method: 'POST', token }),
};
