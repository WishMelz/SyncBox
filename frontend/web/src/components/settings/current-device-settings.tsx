import { useEffect, useRef, useState, type FormEvent } from 'react';
import { Laptop, Copy, Fingerprint } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { devicesApi, type Device } from '@/services/devices';
import { ApiError } from '@/services/api';

export function CurrentDeviceSettings({
  token,
  deviceId,
  disabled,
  onSavingChange,
  onRenamed,
  onExpired,
}: {
  token: string;
  deviceId?: string | null;
  disabled: boolean;
  onSavingChange: (saving: boolean) => void;
  onRenamed: (device: Device) => void;
  onExpired: () => void;
}) {
  const [device, setDevice] = useState<Device | null>(null);
  const [name, setName] = useState('');
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const [retry, setRetry] = useState(0);
  const saveLock = useRef(false);
  const expire = useRef(onExpired);
  expire.current = onExpired;
  useEffect(() => {
    let active = true;
    setLoading(true);
    setDevice(null);
    setError('');
    setNotice('');
    if (!deviceId) {
      setLoading(false);
      setError('当前设备未登记，请重新登录后重试。');
      return;
    }
    void devicesApi
      .list(token)
      .then((devices) => {
        if (!active) return;
        const current = devices.find((item) => item.id === deviceId);
        if (!current) {
          setError('当前设备已移除，请重新登录后重试。');
          return;
        }
        setDevice(current);
        setName(current.name);
      })
      .catch((e: unknown) => {
        if (!active) return;
        if (e instanceof ApiError && e.status === 401) expire.current();
        else setError('无法读取设备名称，请重试。');
      })
      .finally(() => {
        if (active) setLoading(false);
      });
    return () => {
      active = false;
    };
  }, [token, deviceId, retry]);
  async function save(event: FormEvent) {
    event.preventDefault();
    const value = name.trim();
    if (!device || !value || value === device.name || disabled || saveLock.current) return;
    saveLock.current = true;
    setSaving(true);
    onSavingChange(true);
    setError('');
    setNotice('');
    try {
      const updated = await devicesApi.rename(token, device.id, value);
      setDevice(updated);
      setName(updated.name);
      onRenamed(updated);
      setNotice('设备名称已保存');
    } catch (e) {
      if (e instanceof ApiError && e.status === 401) onExpired();
      else setError(e instanceof Error ? e.message : '保存失败，请重试。');
    } finally {
      saveLock.current = false;
      setSaving(false);
      onSavingChange(false);
    }
  }
  async function copyId() {
    if (!device) return;
    try {
      await navigator.clipboard.writeText(device.id);
      setNotice('设备 ID 已复制');
    } catch {
      setError('复制失败，请选中设备 ID 手动复制。');
    }
  }
  return (
    <section className="settings-section" aria-labelledby="current-device-title">
      <h3 id="current-device-title">
        <Laptop size={20} />
        当前设备
      </h3>
      <p>为这台设备起个名字，方便识别消息来源。</p>
      {loading ? (
        <p role="status">正在读取设备名称…</p>
      ) : (
        device && (
          <>
            <form className="settings-form" onSubmit={save}>
              <label className="field-label" htmlFor="current-device-name">
                设备名称
                <input
                  id="current-device-name"
                  value={name}
                  required
                  maxLength={80}
                  disabled={disabled || saving}
                  placeholder="例如：办公电脑、家里的平板"
                  aria-describedby="current-device-name-hint"
                  onChange={(e) => {
                    setName(e.target.value);
                    setNotice('');
                    setError('');
                  }}
                />
              </label>
              <small id="current-device-name-hint">
                最多 80 个字符，新发送的消息将使用这个名称。
              </small>
              <Button
                disabled={disabled || saving || !name.trim() || name.trim() === device.name}
                type="submit"
              >
                {saving ? '保存中…' : '保存设备名称'}
              </Button>
            </form>
            <details className="device-identity-details">
              <summary>设备标识与浏览器绑定</summary>
              <div className="device-identity">
                <label htmlFor="current-device-id">当前设备标识</label>
                <div className="device-id-row">
                  <input
                    id="current-device-id"
                    readOnly
                    value={device.id}
                    onFocus={(e) => e.target.select()}
                  />
                  <button
                    type="button"
                    className="icon-btn"
                    onClick={() => void copyId()}
                    aria-label="复制设备 ID"
                    title="复制设备 ID"
                  >
                    <Copy size={15} />
                  </button>
                </div>
                <span className="device-binding">
                  <Fingerprint size={14} />
                  {device.identityMode === 'fingerprint'
                    ? '已绑定当前浏览器'
                    : '尚未启用指纹识别，请刷新页面重试'}
                </span>
                <small>
                  指纹一致时，普通窗口、隐私窗口和清除站点数据后登录均复用此 ID。
                  隐私保护可能改变指纹；配置相同的设备也可能被识别为同一台。指纹不用于免密登录。
                </small>
              </div>
            </details>
          </>
        )
      )}
      {error && (
        <p role="alert" className="device-settings-error">
          {error}
        </p>
      )}
      {!loading && !device && deviceId && (
        <Button
          variant="outline"
          disabled={disabled}
          onClick={() => setRetry((value) => value + 1)}
        >
          重新读取
        </Button>
      )}
      {notice && (
        <p role="status" className="device-settings-notice">
          {notice}
        </p>
      )}
    </section>
  );
}
