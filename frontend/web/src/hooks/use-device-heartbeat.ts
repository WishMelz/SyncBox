import { useEffect } from 'react';
import { devicesApi } from '@/services/devices';

export function useDeviceHeartbeat(token: string) {
  useEffect(() => {
    let active = true;
    const beat = () => {
      if (active && !document.hidden) void devicesApi.heartbeat(token).catch(() => undefined);
    };
    const onVisible = () => {
      if (!document.hidden) beat();
    };
    beat();
    const timer = window.setInterval(beat, 30_000);
    document.addEventListener('visibilitychange', onVisible);
    return () => {
      active = false;
      window.clearInterval(timer);
      document.removeEventListener('visibilitychange', onVisible);
    };
  }, [token]);
}
