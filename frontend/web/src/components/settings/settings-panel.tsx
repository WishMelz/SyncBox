import { CurrentDeviceSettings } from './current-device-settings';
import type { Device } from '@/services/devices';
import { useEffect, useRef, useState, type FormEvent } from 'react';
import { Clock3, ShieldCheck, Trash2, X, ArrowLeft, Download } from 'lucide-react';
import QRCode from 'qrcode';
import { Button } from '@/components/ui/button';
import { formatBytes } from '@/lib/attachments';
import { settingsApi, type Settings } from '@/services/settings';
import { ApiError } from '@/services/api';

type SecurityAction = 'enable' | 'disable' | 'reset' | null;
export function SettingsPanel({
  token,
  deviceId,
  onDeviceRenamed,
  onClose,
  onShowDevices,
  onReset,
  onExpired,
  embedded = false,
  onNavigationLockChanged,
  accountName,
  onLogout,
}: {
  token: string;
  deviceId?: string | null;
  onDeviceRenamed: (device: Device) => void;
  onClose: () => void;
  onShowDevices: () => void;
  onReset: () => void;
  onExpired: () => void;
  embedded?: boolean;
  onNavigationLockChanged?: (locked: boolean) => void;
  accountName?: string;
  onLogout?: () => Promise<void>;
}) {
  const [settings, setSettings] = useState<Settings | null>(null);
  const [enabled, setEnabled] = useState(false),
    [days, setDays] = useState('30');
  const [busy, setBusy] = useState(false),
    [error, setError] = useState(''),
    [notice, setNotice] = useState('');
  const [action, setAction] = useState<SecurityAction>(null);
  const [password, setPassword] = useState(''),
    [code, setCode] = useState(''),
    [confirmation, setConfirmation] = useState('');
  const [setup, setSetup] = useState<{ secret: string; qr: string } | null>(null);
  const [recovery, setRecovery] = useState<string[]>([]),
    [saved, setSaved] = useState(false);
  const panel = useRef<HTMLDivElement>(null);
  const canClose = !busy && (!recovery.length || saved);
  useEffect(() => {
    onNavigationLockChanged?.(!canClose);
    return () => onNavigationLockChanged?.(false);
  }, [canClose, onNavigationLockChanged]);
  useEffect(() => {
    const before = document.activeElement as HTMLElement | null;
    panel.current?.focus();
    return () => before?.focus();
  }, []);
  function accept(value: Settings) {
    setSettings(value);
    setEnabled(value.cleanup.enabled);
    setDays(String(value.cleanup.idleDays));
  }
  async function load() {
    setError('');
    try {
      accept(await settingsApi.get(token));
    } catch (e) {
      if (e instanceof ApiError && e.status === 401) onExpired();
      else setError('无法加载设置，请重试。');
    }
  }
  useEffect(() => {
    void load();
  }, [token]);
  function start(next: SecurityAction) {
    setAction(next);
    setPassword('');
    setCode('');
    setConfirmation('');
    setSetup(null);
    setError('');
    setNotice('');
  }
  async function saveCleanup(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError('');
    setNotice('');
    try {
      accept(await settingsApi.cleanup(token, enabled, Number(days)));
      setNotice('文件清理设置已保存。');
    } catch (e) {
      if (e instanceof ApiError && e.status === 401) onExpired();
      else setError(e instanceof Error ? e.message : '保存失败，请重试。');
    } finally {
      setBusy(false);
    }
  }
  async function downloadBackup() {
    setBusy(true);
    setError('');
    setNotice('');
    try {
      const backup = await settingsApi.backup(token);
      const url = URL.createObjectURL(backup.blob);
      const link = document.createElement('a');
      link.href = url;
      link.download =
        backup.filename ?? `syncbox-backup-${new Date().toISOString().slice(0, 10)}.sqlite`;
      link.click();
      URL.revokeObjectURL(url);
      setNotice(
        `${backup.verified ? '备份已校验并下载' : '备份已下载（当前浏览器未提供本地校验能力）'}（${formatBytes(backup.size)}，SHA-256 ${backup.sha256.slice(0, 12)}…）。`,
      );
    } catch (e) {
      if (e instanceof ApiError && e.status === 401) onExpired();
      else setError(e instanceof Error ? e.message : '备份下载失败，请重试。');
    } finally {
      setBusy(false);
    }
  }
  async function secure(e: FormEvent) {
    e.preventDefault();
    if (busy) return;
    setBusy(true);
    setError('');
    setNotice('');
    const body = { password, ...(code.trim() ? { code: code.trim() } : {}) };
    try {
      if (action === 'reset') {
        await settingsApi.reset(token, { ...body, confirmation });
        onReset();
        return;
      }
      if (action === 'disable') {
        accept(await settingsApi.disable(token, body));
        start(null);
        setNotice('两步认证已关闭，其他设备需要重新登录。');
      } else if (!setup) {
        const result = await settingsApi.begin(token, body);
        setSetup({
          secret: result.secret,
          qr: await QRCode.toDataURL(result.otpauthUri, { width: 200, margin: 2 }),
        });
      } else {
        const result = await settingsApi.enable(token, body);
        setRecovery(result.recoveryCodes);
        setSaved(false);
        start(null);
        setSettings((s) =>
          s
            ? { ...s, twoFactorEnabled: true, recoveryCodesRemaining: result.recoveryCodes.length }
            : s,
        );
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : '操作失败，请重试。');
    } finally {
      setBusy(false);
    }
  }
  return (
    <div
      className={`settings-backdrop${embedded ? ' settings-embedded' : ''}`}
      onClick={() => !embedded && canClose && onClose()}
    >
      <div
        ref={panel}
        tabIndex={-1}
        className="settings-panel"
        role={embedded ? 'region' : 'dialog'}
        aria-modal={embedded ? undefined : true}
        aria-labelledby="settings-title"
        onClick={(e) => e.stopPropagation()}
        onKeyDown={(e) => {
          if (e.key === 'Escape' && canClose) onClose();
          if (e.key === 'Tab' && !embedded) {
            const nodes = [
              ...(panel.current?.querySelectorAll<HTMLElement>(
                'button:not(:disabled),input:not(:disabled),a[href]',
              ) ?? []),
            ];
            const first = nodes[0],
              last = nodes[nodes.length - 1];
            if (
              e.shiftKey &&
              (document.activeElement === first || document.activeElement === panel.current)
            ) {
              e.preventDefault();
              last?.focus();
            } else if (!e.shiftKey && document.activeElement === last) {
              e.preventDefault();
              first?.focus();
            }
          }
        }}
      >
        <header className="settings-header">
          <div>
            <p className="eyebrow">个人空间</p>
            <h2 id="settings-title">设置</h2>
          </div>
          {!embedded && (
            <button aria-label="关闭设置" disabled={!canClose} onClick={onClose}>
              <X size={22} />
            </button>
          )}
        </header>
        {!action && !recovery.length && (
          <nav className="settings-nav" aria-label="设置分组">
            {[
              ['current-device-title', '设备'],
              ['cleanup-title', '文件'],
              ['security-title', '安全'],
              ['danger-title', '清空空间'],
            ].map(([id, label]) => (
              <button
                key={id}
                onClick={() =>
                  panel.current?.querySelector(`#${id}`)?.scrollIntoView({ block: 'start' })
                }
              >
                {label}
              </button>
            ))}
          </nav>
        )}
        <div className="settings-content">
          {error && (
            <p role="alert" className="settings-error">
              {error}
            </p>
          )}
          {notice && (
            <p role="status" className="settings-notice">
              {notice}
            </p>
          )}
          {!settings ? (
            <div>
              <p>正在加载设置…</p>
              <Button variant="outline" onClick={() => void load()}>
                重新加载
              </Button>
            </div>
          ) : (
            <>
              {recovery.length > 0 ? (
                <section className="settings-section">
                  <h3>
                    <ShieldCheck size={20} />
                    两步认证已开启
                  </h3>
                  <p>
                    请保存以下恢复码。验证器无法使用时，可用恢复码代替动态码登录，每个只能使用一次。
                  </p>
                  <p>
                    恢复码只显示这一次，请保存在安全的位置。其他设备需要重新登录；尚未支持两步认证的旧客户端暂时无法登录。
                  </p>
                  <div className="recovery-codes">
                    {recovery.map((item) => (
                      <code key={item}>{item}</code>
                    ))}
                  </div>
                  <label className="settings-check">
                    <input
                      type="checkbox"
                      checked={saved}
                      onChange={(e) => setSaved(e.target.checked)}
                    />
                    我已安全保存恢复码
                  </label>
                  <Button disabled={!saved} onClick={() => setRecovery([])}>
                    完成
                  </Button>
                </section>
              ) : action ? (
                <section className="settings-section">
                  <button className="settings-back" disabled={busy} onClick={() => start(null)}>
                    <ArrowLeft size={16} />
                    返回设置
                  </button>
                  <h3>
                    {action === 'reset'
                      ? '删除所有数据'
                      : action === 'disable'
                        ? '关闭两步认证'
                        : '开启两步认证'}
                  </h3>
                  <p>
                    {action === 'reset'
                      ? '这将永久删除账号、会话、消息、图片、附件、设备及设置，并退出所有设备。之后需重新设置账号，任何能访问此服务的人都能进行首次设置。此操作无法撤销，已有外部备份不会删除。'
                      : action === 'disable'
                        ? '关闭后，登录只需用户名和密码。其他设备会退出登录。'
                        : '使用 Google Authenticator、Microsoft Authenticator 等验证器生成动态码。开启后，其他设备会退出登录，旧版客户端可能无法登录。'}
                  </p>
                  <form onSubmit={secure} className="settings-form">
                    <label className="field-label">
                      当前密码
                      <input
                        type="password"
                        autoComplete="current-password"
                        required
                        minLength={6}
                        maxLength={128}
                        value={password}
                        disabled={busy || !!setup}
                        onChange={(e) => setPassword(e.target.value)}
                      />
                    </label>
                    {setup && (
                      <div className="totp-setup">
                        <p>用验证器扫描二维码，或手动输入下方密钥。请在 10 分钟内完成验证。</p>
                        <img src={setup.qr} alt="验证器绑定二维码" />
                        <code>{setup.secret}</code>
                      </div>
                    )}
                    {(setup || settings.twoFactorEnabled) && (
                      <label className="field-label">
                        {setup ? '6 位动态码' : '动态码或恢复码'}
                        <input
                          autoComplete="one-time-code"
                          required
                          maxLength={40}
                          value={code}
                          onChange={(e) => setCode(e.target.value)}
                          disabled={busy}
                        />
                        <small>动态码只能使用一次；刚用过时请等待下一组。</small>
                      </label>
                    )}
                    {action === 'reset' && (
                      <label className="field-label">
                        输入“删除所有数据”以确认
                        <input
                          autoComplete="off"
                          required
                          value={confirmation}
                          onChange={(e) => setConfirmation(e.target.value)}
                          disabled={busy}
                        />
                      </label>
                    )}
                    <Button
                      type="submit"
                      variant={action === 'reset' ? 'destructive' : 'default'}
                      disabled={busy || (action === 'reset' && confirmation !== '删除所有数据')}
                    >
                      {busy
                        ? '处理中…'
                        : action === 'reset'
                          ? '永久删除所有数据'
                          : action === 'disable'
                            ? '确认关闭'
                            : setup
                              ? '验证并开启'
                              : '下一步：绑定验证器'}
                    </Button>
                  </form>
                </section>
              ) : (
                <>
                  {embedded && onLogout && (
                    <section className="settings-section settings-account" aria-label="当前账号">
                      <span>{accountName}</span>
                      <Button
                        variant="ghost"
                        disabled={busy}
                        onClick={async () => {
                          setBusy(true);
                          try {
                            await onLogout();
                          } catch {
                            setError('退出失败，请重试。');
                          } finally {
                            setBusy(false);
                          }
                        }}
                      >
                        退出登录
                      </Button>
                    </section>
                  )}
                  <CurrentDeviceSettings
                    token={token}
                    deviceId={deviceId}
                    disabled={busy}
                    onSavingChange={setBusy}
                    onRenamed={onDeviceRenamed}
                    onExpired={onExpired}
                  />
                  <button className="settings-devices-link" onClick={onShowDevices} disabled={busy}>
                    管理已登记设备 →
                  </button>
                  <section className="settings-section">
                    <h3 id="cleanup-title">
                      <Clock3 size={20} />
                      闲置文件清理
                    </h3>
                    <p>自动删除长期未访问的图片和附件，保留会话及消息文字。</p>
                    <p className="settings-storage">
                      当前保存 {settings.storage.fileCount} 个文件 ·{' '}
                      {formatBytes(settings.storage.bytes)}
                    </p>
                    <form onSubmit={saveCleanup} className="settings-form">
                      <label className="settings-toggle">
                        <span>自动清理闲置文件</span>
                        <input
                          type="checkbox"
                          role="switch"
                          checked={enabled}
                          disabled={busy}
                          onChange={(e) => setEnabled(e.target.checked)}
                        />
                      </label>
                      <label className="field-label">
                        文件保留天数
                        <div className="settings-days">
                          <input
                            type="number"
                            min={1}
                            max={3650}
                            step={1}
                            required
                            value={days}
                            disabled={busy || !enabled}
                            onChange={(e) => setDays(e.target.value)}
                          />
                          <span>天</span>
                        </div>
                      </label>
                      <p>
                        按上传、预览或下载的最近时间计算，每 10
                        分钟检查一次。仅查看文件列表不算访问。开启后，已超过期限的文件也会被清理，且无法恢复。
                      </p>
                      {settings.cleanup.lastRunAt && (
                        <small>
                          上次检查：{new Date(settings.cleanup.lastRunAt).toLocaleString('zh-CN')}
                          ，清理 {settings.cleanup.lastDeletedCount} 个文件
                        </small>
                      )}
                      <Button disabled={busy} type="submit">
                        {busy ? '保存中…' : '保存清理设置'}
                      </Button>
                    </form>
                  </section>
                  <section className="settings-section">
                    <h3 id="security-title">
                      <ShieldCheck size={20} />
                      两步认证
                    </h3>
                    <p>登录时，在密码之外再验证一组动态码，保护你的私人空间。</p>
                    <label className="settings-toggle">
                      <span>{settings.twoFactorEnabled ? '已开启两步认证' : '未开启两步认证'}</span>
                      <input
                        type="checkbox"
                        role="switch"
                        aria-label="两步认证"
                        checked={settings.twoFactorEnabled}
                        disabled={busy}
                        onChange={() => start(settings.twoFactorEnabled ? 'disable' : 'enable')}
                      />
                    </label>
                    {settings.twoFactorEnabled && (
                      <small>
                        剩余 {settings.recoveryCodesRemaining}{' '}
                        个恢复码。需要新恢复码时，可关闭后重新开启。
                      </small>
                    )}
                  </section>
                  <section className="settings-section">
                    <h3>
                      <Download size={20} />
                      数据备份
                    </h3>
                    <p>
                      下载当前 SQLite
                      数据快照，包含会话、消息、设置和附件；支持时会在下载前校验完整性。
                    </p>
                    <Button disabled={busy} variant="outline" onClick={() => void downloadBackup()}>
                      {busy ? '正在准备…' : '下载数据库备份'}
                    </Button>
                    <small>
                      恢复备份前请停止后端服务，并先保留当前数据库副本；替换数据库时同时处理 WAL
                      文件。
                    </small>
                  </section>
                  <section className="settings-section settings-danger">
                    <h3 id="danger-title">
                      <Trash2 size={20} />
                      清空个人空间
                    </h3>
                    <p>
                      清空账号和全部内容，恢复为首次使用状态。删除前需要验证身份，操作无法撤销。
                    </p>
                    <Button disabled={busy} variant="destructive" onClick={() => start('reset')}>
                      清空个人空间
                    </Button>
                  </section>
                </>
              )}
            </>
          )}
        </div>
      </div>
    </div>
  );
}
