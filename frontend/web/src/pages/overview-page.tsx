import {
  ArrowRight,
  Box,
  CheckCircle2,
  Database,
  MonitorSmartphone,
  RefreshCw,
  Server,
  WifiOff,
} from 'lucide-react';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { useHealth } from '@/hooks/use-health';

const platforms = [
  {
    title: 'Apple 客户端',
    description: '为 iPhone、iPad 和 Mac 构建一致体验。',
    detail: 'SwiftUI',
    icon: MonitorSmartphone,
  },
  {
    title: 'Web 工作空间',
    description: '从手机到桌面，随时进入工作空间。',
    detail: 'React · Vite · shadcn/ui',
    icon: Box,
  },
  {
    title: '数据服务',
    description: '为多端应用提供统一的数据接口。',
    detail: 'NestJS · SQLite',
    icon: Database,
  },
];

export function OverviewPage() {
  const { state, refresh } = useHealth();
  return (
    <div className="space-y-8">
      <section id="overview" className="scroll-mt-6">
        <p className="mb-3 text-xs font-semibold tracking-[0.2em] text-primary">
          YOUR CONNECTED WORKSPACE
        </p>
        <h1 className="text-3xl font-semibold tracking-tight sm:text-4xl">欢迎来到 SyncBox</h1>
        <p className="mt-3 max-w-xl text-sm leading-7 text-muted-foreground">
          你的多端工作空间已就绪。从这里查看服务状态，开始构建属于你的同步体验。
        </p>
      </section>
      <section className="relative overflow-hidden rounded-2xl bg-[#1c2340] p-6 text-white sm:p-9">
        <div
          aria-hidden="true"
          className="absolute -right-10 -top-24 size-72 rounded-full border-[36px] border-white/5"
        />
        <div className="relative max-w-lg">
          <Badge className="mb-5 border-white/20 bg-white/10 text-white">初始工作空间</Badge>
          <h2 className="text-2xl font-medium tracking-tight">连接每一端，从这里开始。</h2>
          <p className="mt-3 text-sm leading-7 text-slate-300">
            基础框架已搭建。文件管理与同步功能将在后续业务开发中接入。
          </p>
          <Button asChild variant="secondary" className="mt-6">
            <a href="#services">
              检查服务连接
              <ArrowRight size={16} />
            </a>
          </Button>
        </div>
      </section>
      <section aria-label="应用组成" className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
        {platforms.map(({ title, description, detail, icon: Icon }) => (
          <Card key={title} className="shadow-none">
            <CardHeader>
              <span className="mb-3 flex size-10 items-center justify-center rounded-xl bg-accent text-primary">
                <Icon size={20} />
              </span>
              <CardTitle className="text-base">{title}</CardTitle>
            </CardHeader>
            <CardContent>
              <p className="min-h-12 text-sm leading-6 text-muted-foreground">{description}</p>
              <p className="mt-5 border-t pt-4 text-xs text-muted-foreground">{detail}</p>
            </CardContent>
          </Card>
        ))}
      </section>
      <section id="services" className="scroll-mt-6">
        <Card className="shadow-none">
          <CardHeader className="flex flex-row flex-wrap items-center justify-between gap-4">
            <div>
              <CardTitle className="text-lg">服务连接</CardTitle>
              <p className="mt-2 text-sm text-muted-foreground">实时检查后端与数据库是否可用</p>
            </div>
            <Button
              variant="outline"
              size="sm"
              disabled={state.status === 'loading'}
              onClick={() => void refresh()}
            >
              <RefreshCw size={15} className={state.status === 'loading' ? 'animate-spin' : ''} />
              刷新状态
            </Button>
          </CardHeader>
          <CardContent>
            <div
              role="status"
              aria-live="polite"
              className="flex flex-wrap items-center gap-4 rounded-xl border bg-background p-4"
            >
              <span className="rounded-lg bg-white p-3">
                <Server size={22} className="text-muted-foreground" />
              </span>
              <div className="min-w-0 flex-1">
                <p className="text-sm font-medium">SyncBox API</p>
                <p className="mt-1 break-words text-xs leading-5 text-muted-foreground">
                  {state.status === 'loading'
                    ? '正在检查连接…'
                    : state.status === 'success'
                      ? `SQLite 连接正常 · 检查于 ${state.checkedAt.toLocaleTimeString('zh-CN')}`
                      : state.message}
                </p>
              </div>
              <Badge
                variant="outline"
                className={
                  state.status === 'success'
                    ? 'border-emerald-200 bg-emerald-50 text-emerald-700'
                    : ''
                }
              >
                {state.status === 'success' ? (
                  <CheckCircle2 size={12} />
                ) : state.status === 'error' ? (
                  <WifiOff size={12} />
                ) : null}
                {state.status === 'loading'
                  ? '检查中'
                  : state.status === 'success'
                    ? '已连接'
                    : '未连接'}
              </Badge>
            </div>
          </CardContent>
        </Card>
      </section>
      <footer className="text-xs leading-6 text-muted-foreground">
        SyncBox · 让每个设备成为工作空间的一部分
      </footer>
    </div>
  );
}
