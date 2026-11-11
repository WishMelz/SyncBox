import { useState, useEffect, type FormEvent } from 'react';
import { ArrowRight, Laptop, Smartphone, ShieldCheck } from 'lucide-react';
import { BrandIcon } from '@/components/ui/brand-icon';
import { Button } from '@/components/ui/button';
import { ApiError } from '@/services/api';
import { authApi, type Session } from '@/services/auth';
export function LoginPage({ onLogin }: { onLogin: (s: Session) => Promise<void> }) {
  const [twoFactor, setTwoFactor] = useState(false);
  const [register, setRegister] = useState(false),
    [ready, setReady] = useState(false),
    [busy, setBusy] = useState(false),
    [error, setError] = useState('');
  async function loadStatus() {
    setError('');
    setReady(false);
    try {
      const status = await authApi.status();
      setRegister(!status.initialized);
      setReady(true);
    } catch {
      setError('暂时无法连接服务器，请检查网络或服务状态后重试。');
    }
  }
  useEffect(() => {
    void loadStatus();
  }, []);
  async function submit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const data = new FormData(e.currentTarget);
    setBusy(true);
    setError('');
    try {
      if (register && data.get('password') !== data.get('confirmPassword')) {
        setError('两次输入的密码不一致');
        return;
      }
      const s = register
        ? await authApi.setup(String(data.get('username')), String(data.get('password')))
        : await authApi.login(
            String(data.get('username')),
            String(data.get('password')),
            String(data.get('code') ?? '').trim(),
          );
      setRegister(false);
      setTwoFactor(false);
      await onLogin(s);
    } catch (e) {
      if (e instanceof ApiError && e.code === 'TWO_FACTOR_REQUIRED') {
        setTwoFactor(true);
        setError('密码已验证，请输入验证器动态码或恢复码。');
      }
      if (e instanceof ApiError && e.status === 409) {
        setRegister(false);
      }
      setError(e instanceof Error ? e.message : '连接失败');
    } finally {
      setBusy(false);
    }
  }
  return (
    <div className="login-grid">
      <section className="login-story">
        <div className="brand">
          <BrandIcon size={36} />
          SyncBox
        </div>
        <div>
          <p className="eyebrow">你的私人共享空间</p>
          <h1>
            随手发送，
            <br />
            换台设备继续。
          </h1>
          <p className="story-copy">
            文字、图片和文件，集中保存在这里。
            <br />
            登录同一账号，随时在其他设备上查看。
          </p>
          <div className="device-illustration">
            <Smartphone size={42} />
            <span>······</span>
            <BrandIcon size={52} />
            <span>······</span>
            <Laptop size={48} />
          </div>
        </div>
        <p className="privacy">
          <ShieldCheck size={16} /> 私有部署 · 数据保存在自己的服务器
        </p>
      </section>
      <section className="login-form">
        <div className="w-full max-w-sm">
          <p className="eyebrow">欢迎使用 SyncBox</p>
          <h2 className="mb-2 text-3xl font-semibold">
            {!ready ? '连接你的空间' : register ? '设置你的账号' : '欢迎回来'}
          </h2>
          <p className="mb-8 text-sm text-muted-foreground">
            {!ready
              ? error
                ? '连接未完成，请检查下方提示后重试。'
                : '正在检查服务状态，请稍候。'
              : register
                ? '首次使用，请设置用户名和密码。其他设备使用同一账号登录。'
                : '登录后，继续查看和分享你的内容。'}
          </p>
          <form onSubmit={submit} className="space-y-5">
            <label className="field-label">
              用户名
              <input
                name="username"
                type="text"
                required
                autoComplete="username"
                maxLength={254}
                placeholder={register ? '设置用户名' : '输入用户名'}
              />
            </label>
            <label className="field-label">
              密码
              <input
                name="password"
                type="password"
                minLength={6}
                maxLength={128}
                required
                autoComplete={register ? 'new-password' : 'current-password'}
                placeholder={register ? '设置密码，至少 6 位' : '输入密码'}
              />
            </label>
            {register && (
              <label className="field-label">
                确认密码
                <input
                  name="confirmPassword"
                  type="password"
                  required
                  minLength={6}
                  maxLength={128}
                  autoComplete="new-password"
                  placeholder="再次输入密码"
                />
              </label>
            )}
            {!register && twoFactor && (
              <label className="field-label">
                两步验证码
                <input
                  name="code"
                  autoFocus
                  autoComplete="one-time-code"
                  required
                  maxLength={40}
                  placeholder="输入验证器动态码或备用恢复码"
                />
                <small>密码已验证。请输入验证器中的 6 位动态码，或一个未使用的恢复码。</small>
              </label>
            )}
            {error && (
              <p role="alert" className="error-note">
                {error}
              </p>
            )}
            <Button className="w-full h-11" disabled={busy || !ready}>
              {busy ? (register ? '正在设置…' : '正在登录…') : register ? '设置并进入' : '登录'}
              <ArrowRight size={16} />
            </Button>
          </form>
          {!ready && (
            <button className="mt-6 text-sm text-primary" onClick={loadStatus}>
              重新连接
            </button>
          )}
          <p className="mt-10 text-xs leading-6 text-muted-foreground">
            服务器：{window.location.host}
            <br />
            一个私人空间，一个账号，供你的所有设备使用。
          </p>
        </div>
      </section>
    </div>
  );
}
