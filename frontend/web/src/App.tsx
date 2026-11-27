import { cachedDeviceId, cacheDeviceId, deviceFingerprint } from '@/lib/device-identity';
import { useEffect, useRef, useState } from 'react';
import { authApi, type Session } from '@/services/auth';
import { devicesApi } from '@/services/devices';
import { ApiError } from '@/services/api';
import { mediaCache } from '@/lib/media-cache';
import { LoginPage } from '@/pages/login-page';
import { WorkspacePage } from '@/pages/workspace-page';
const key = 'syncbox-session';
type SessionStorageKind = 'local' | 'session';

function getStorage(kind: SessionStorageKind): Storage | null {
  try {
    return kind === 'local' ? localStorage : sessionStorage;
  } catch {
    return null;
  }
}

function readStoredSession(): { session: Session | null; storage: SessionStorageKind } {
  for (const kind of ['local', 'session'] as const) {
    const storage = getStorage(kind);
    if (!storage) continue;
    try {
      const value = storage.getItem(key);
      if (value) return { session: JSON.parse(value) as Session, storage: kind };
    } catch {
      try {
        storage.removeItem(key);
      } catch {
        // Continue with the next storage fallback.
      }
    }
  }
  return { session: null, storage: 'session' };
}

function storeSession(session: Session, storage: SessionStorageKind) {
  const serialized = JSON.stringify(session);
  const target = getStorage(storage);
  let actual = storage;
  try {
    if (!target) throw new Error('storage unavailable');
    target.setItem(key, serialized);
  } catch {
    getStorage('session')?.setItem(key, serialized);
    actual = 'session';
  }
  getStorage(actual === 'local' ? 'session' : 'local')?.removeItem(key);
}
export function App() {
  const [stored] = useState(readStoredSession);
  const [session, setSession] = useState<Session | null>(stored.session);
  const storageKind = useRef<SessionStorageKind>(stored.storage);
  const [checking, setChecking] = useState(!!session),
    [error, setError] = useState('');
  function clear() {
    mediaCache.clear();
    getStorage('local')?.removeItem(key);
    getStorage('session')?.removeItem(key);
    setSession(null);
    setChecking(false);
  }
  async function bindDevice(s: Session) {
    const id = s.user.deviceId ?? cachedDeviceId(s.user.id);
    const identity = {
      identityMode: 'fingerprint' as const,
      fingerprint: deviceFingerprint(),
    };
    let device;
    try {
      const existing = id
        ? (await devicesApi.list(s.accessToken)).find((d) => d.id === id)
        : undefined;
      device = await devicesApi.register(s.accessToken, {
        ...(id ? { id } : {}),
        name: existing?.name ?? 'Web 浏览器',
        platform: 'web',
        ...identity,
      });
    } catch (e) {
      if (e instanceof ApiError && (e.status === 404 || e.status === 409)) {
        device = await devicesApi.register(s.accessToken, {
          name: 'Web 浏览器',
          platform: 'web',
          ...identity,
        });
      } else {
        throw e;
      }
    }
    cacheDeviceId(s.user.id, device.id);
    s = { ...s, user: { ...s.user, deviceId: device.id } };
    return s;
  }
  async function login(s: Session, remember: boolean) {
    let bound: Session;
    try {
      bound = await bindDevice(s);
    } catch (e) {
      await authApi.logout(s.accessToken).catch(() => {});
      throw e;
    }
    storageKind.current = remember ? 'local' : 'session';
    storeSession(bound, storageKind.current);
    setSession(bound);
    setChecking(false);
  }
  useEffect(() => {
    if (!session) return;
    let active = true;
    authApi
      .me(session.accessToken)
      .then(async (user) => {
        if (!active) return;
        const bound = await bindDevice({ ...session, user });
        if (active) {
          setSession((current) => {
            if (!current) return current;
            const next = { ...current, user: bound.user };
            storeSession(next, storageKind.current);
            return next;
          });
          setChecking(false);
        }
      })
      .catch((e) => {
        if (!active) return;
        if (e instanceof ApiError && e.status === 401) clear();
        else {
          setError('无法连接服务，请检查网络后重试');
          setChecking(false);
        }
      });
    return () => {
      active = false;
    };
  }, [session?.accessToken]);
  if (checking) return <div className="grid min-h-svh place-items-center">正在连接个人空间…</div>;
  if (!session) return <LoginPage onLogin={login} />;
  return (
    <>
      <WorkspacePage
        session={session}
        onExpired={clear}
        onLogout={async () => {
          await authApi.logout(session.accessToken);
          clear();
        }}
      />
      {error && (
        <div role="alert" className="connection-error" onClick={() => setError('')}>
          {error}
        </div>
      )}
    </>
  );
}
