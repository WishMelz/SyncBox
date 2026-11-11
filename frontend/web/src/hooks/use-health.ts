import { useCallback, useEffect, useRef, useState } from 'react';
import { getHealth, type HealthResponse } from '@/services/health';

type HealthState =
  | { status: 'loading' }
  | { status: 'success'; data: HealthResponse; checkedAt: Date }
  | { status: 'error'; message: string };

export function useHealth() {
  const [state, setState] = useState<HealthState>({ status: 'loading' });
  const controller = useRef<AbortController | null>(null);
  const refresh = useCallback(async () => {
    controller.current?.abort();
    const current = new AbortController();
    controller.current = current;
    setState({ status: 'loading' });
    const timeout = setTimeout(() => current.abort(new Error('连接超时，请确认后端已启动')), 8000);
    try {
      const data = await getHealth(current.signal);
      if (controller.current === current)
        setState({ status: 'success', data, checkedAt: new Date() });
    } catch (error) {
      if (controller.current === current)
        setState({
          status: 'error',
          message: error instanceof Error ? error.message : '无法连接服务',
        });
    } finally {
      clearTimeout(timeout);
    }
  }, []);
  useEffect(() => {
    void refresh();
    return () => {
      controller.current?.abort();
      controller.current = null;
    };
  }, [refresh]);
  return { state, refresh };
}
