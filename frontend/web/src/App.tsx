import { cachedDeviceId, cacheDeviceId, deviceFingerprint } from '@/lib/device-identity';
import { useEffect, useState } from 'react';
import { authApi, type Session } from '@/services/auth';
import { devicesApi } from '@/services/devices';
import { ApiError } from '@/services/api';
import { LoginPage } from '@/pages/login-page';
import { WorkspacePage } from '@/pages/workspace-page';
const key = 'syncbox-session';
export function App() {
  const [session, setSession] = useState<Session | null>(() => {
    try {
      return JSON.parse(sessionStorage.getItem(key) ?? 'null');
    } catch {
      return null;
    }
  });
  const [checking, setChecking] = useState(!!session),
    [error, setError] = useState('');
  function clear() {
    sessionStorage.removeItem(key);
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
  async function login(s: Session) {
    let bound: Session;
    try {
      bound = await bindDevice(s);
    } catch (e) {
      await authApi.logout(s.accessToken).catch(() => {});
      throw e;
    }
    sessionStorage.setItem(key, JSON.stringify(bound));
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
            sessionStorage.setItem(key, JSON.stringify(next));
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
