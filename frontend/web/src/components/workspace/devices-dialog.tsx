import { RefreshCw, X } from 'lucide-react';
import type { Device } from '@/services/devices';

export function DevicesDialog({
  devices,
  currentDeviceId,
  deviceEdit,
  deviceName,
  busy,
  onRefresh,
  onClose,
  onStartEdit,
  onDeviceNameChange,
  onSaveEdit,
  onCancelEdit,
  onRequestRemove,
}: {
  devices: Device[];
  currentDeviceId?: string | null;
  deviceEdit: string | null;
  deviceName: string;
  busy: boolean;
  onRefresh: () => void;
  onClose: () => void;
  onStartEdit: (device: Device) => void;
  onDeviceNameChange: (value: string) => void;
  onSaveEdit: () => void;
  onCancelEdit: () => void;
  onRequestRemove: (device: Device) => void;
}) {
  return (
    <div className="modal-backdrop" onClick={() => !busy && onClose()}>
      <section
        role="dialog"
        aria-modal="true"
        aria-labelledby="modal-title"
        className="modal-card"
        onClick={(e) => e.stopPropagation()}
        onKeyDown={(e) => {
          if (e.key === 'Escape' && !busy) onClose();
        }}
      >
        <div className="flex items-center justify-between">
          <h2 id="modal-title">我的设备</h2>
          <button
            className="device-refresh-button"
            type="button"
            onClick={onRefresh}
            disabled={busy}
            title="刷新设备状态"
          >
            <RefreshCw size={15} />
            刷新
          </button>
          <button aria-label="关闭弹窗" onClick={onClose} disabled={busy}>
            <X size={20} />
          </button>
        </div>
        <div className="device-list">
          {devices.map((d) => (
            <div key={d.id}>
              <span className="device-info">
                {deviceEdit === d.id ? (
                  <input
                    autoFocus
                    value={deviceName}
                    maxLength={80}
                    disabled={busy}
                    aria-label="设备名称"
                    onChange={(e) => onDeviceNameChange(e.target.value)}
                    onKeyDown={(e) => {
                      if (e.key === 'Enter' && !e.nativeEvent.isComposing) {
                        e.preventDefault();
                        onSaveEdit();
                      }
                    }}
                  />
                ) : (
                  <strong>
                    {d.name}
                    {d.id === currentDeviceId && <small className="current-device">当前设备</small>}
                    <small className="device-list-id">ID：{d.id}</small>
                  </strong>
                )}
                <small>
                  {d.platform} ·{' '}
                  <span className={`device-presence ${d.online ? 'online' : 'offline'}`}>
                    <i aria-hidden="true" />
                    {d.online ? '在线' : '离线'}
                  </span>{' '}
                  · 最近活动 {new Date(d.lastSeenAt).toLocaleString('zh-CN')}
                </small>
              </span>
              {d.id === currentDeviceId ? (
                deviceEdit === d.id ? (
                  <>
                    <button
                      className="device-edit-button"
                      disabled={busy || !deviceName.trim()}
                      onClick={onSaveEdit}
                    >
                      {busy ? '保存中…' : '保存'}
                    </button>
                    <button className="device-edit-button" disabled={busy} onClick={onCancelEdit}>
                      取消
                    </button>
                  </>
                ) : (
                  <button className="device-edit-button" onClick={() => onStartEdit(d)}>
                    改名
                  </button>
                )
              ) : (
                <button
                  className="device-edit-button device-remove-button"
                  disabled={busy}
                  onClick={() => onRequestRemove(d)}
                >
                  移除
                </button>
              )}
            </div>
          ))}
        </div>
      </section>
    </div>
  );
}
