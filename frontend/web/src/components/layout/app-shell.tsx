import type { ReactNode } from 'react';
import { LayoutDashboard, Radio, ArrowUpRight } from 'lucide-react';
import { BrandIcon } from '@/components/ui/brand-icon';

const links = [
  { href: '#overview', label: '概览', icon: LayoutDashboard },
  { href: '#services', label: '服务状态', icon: Radio },
];

export function AppShell({ children }: { children: ReactNode }) {
  return (
    <div className="min-h-svh">
      <a
        href="#main"
        className="sr-only focus:not-sr-only focus:fixed focus:z-50 focus:bg-white focus:p-4"
      >
        跳转到主要内容
      </a>
      <aside className="fixed inset-y-0 left-0 hidden w-60 flex-col border-r bg-white px-5 py-8 md:flex">
        <a
          href="#overview"
          className="mb-12 flex items-center gap-3 px-3 text-xl font-semibold tracking-tight"
        >
          <BrandIcon size={38} />
          SyncBox
        </a>
        <p className="mb-3 px-3 text-xs font-medium tracking-widest text-muted-foreground">
          工作空间
        </p>
        <nav aria-label="主导航" className="space-y-2">
          {links.map(({ href, label, icon: Icon }) => (
            <a
              key={href}
              href={href}
              className="flex items-center gap-3 rounded-lg px-3 py-3 text-sm font-medium hover:bg-accent hover:text-primary"
            >
              <Icon size={18} />
              {label}
            </a>
          ))}
        </nav>
        <div className="mt-auto rounded-xl bg-muted p-4 text-xs leading-6 text-muted-foreground">
          SyncBox · 初始工作空间
          <br />
          跨设备，一处开始。
        </div>
      </aside>
      <div className="md:pl-60">
        <header className="flex h-18 items-center justify-between gap-4 border-b bg-white px-5 sm:px-8 lg:px-12">
          <a href="#overview" className="flex items-center gap-2 font-semibold md:hidden">
            <BrandIcon size={28} />
            SyncBox
          </a>
          <span className="hidden text-sm text-muted-foreground md:block">工作空间 / 概览</span>
          <a
            href="/api/v1/health"
            target="_blank"
            rel="noreferrer"
            className="flex items-center gap-1.5 text-xs text-muted-foreground hover:text-primary"
          >
            查看 API 状态
            <ArrowUpRight size={14} />
          </a>
        </header>
        <nav aria-label="移动端导航" className="flex gap-2 border-b bg-white px-5 py-2 md:hidden">
          {links.map(({ href, label }) => (
            <a key={href} href={href} className="rounded-lg px-4 py-2 text-sm hover:bg-accent">
              {label}
            </a>
          ))}
        </nav>
        <main id="main" className="mx-auto max-w-7xl px-5 py-8 sm:px-8 lg:px-12 lg:py-12">
          {children}
        </main>
      </div>
    </div>
  );
}
