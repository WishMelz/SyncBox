import { useEffect, useState } from 'react';
import { RefreshCw } from 'lucide-react';

export function SyncStatus({
  connected,
  lastSyncedAt,
  onRetry,
}: {
  connected: boolean;
  lastSyncedAt: number | null;
  onRetry: () => void;
}) {
  const [now, setNow] = useState(Date.now());
  useEffect(() => {
    const timer = window.setInterval(() => setNow(Date.now()), 15000);
    return () => clearInterval(timer);
  }, []);
  const elapsed = Math.max(0, Math.floor((now - (lastSyncedAt ?? now)) / 60000));
  const label = !connected
    ? '连接中断 · 重试'
    : !lastSyncedAt
      ? '正在连接…'
      : `已同步 · ${elapsed ? `${elapsed} 分钟前` : '刚刚'}`;
  return (
    <button
      type="button"
      className={`sync-status ${connected ? '' : 'sync-interrupted'}`}
      onClick={onRetry}
      title="重新同步"
      aria-label={label}
    >
      <RefreshCw size={12} />
      {label}
    </button>
  );
}
