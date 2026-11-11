export interface HealthResponse {
  status: 'ok';
  service: string;
  database: 'up';
}

export async function getHealth(signal?: AbortSignal): Promise<HealthResponse> {
  const response = await fetch('/api/v1/health', {
    signal,
    headers: { Accept: 'application/json' },
  });
  if (!response.ok) throw new Error(`服务暂不可用（HTTP ${response.status}）`);
  const data = await response.json();
  if (data.status !== 'ok' || data.database !== 'up' || typeof data.service !== 'string') {
    throw new Error('服务返回了无法识别的状态');
  }
  return data;
}
