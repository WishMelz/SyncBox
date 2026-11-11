import { MessageSquare, Settings } from 'lucide-react';

export function MobileWorkspaceNav({
  settings,
  locked,
  onChange,
}: {
  settings: boolean;
  locked: boolean;
  onChange: (settings: boolean) => void;
}) {
  return (
    <nav className="mobile-workspace-nav" aria-label="主导航">
      <button
        type="button"
        aria-current={!settings ? 'page' : undefined}
        disabled={locked}
        onClick={() => onChange(false)}
      >
        <MessageSquare size={23} aria-hidden="true" />
        <span>消息</span>
      </button>
      <button
        type="button"
        aria-current={settings ? 'page' : undefined}
        disabled={locked}
        onClick={() => onChange(true)}
      >
        <Settings size={23} aria-hidden="true" />
        <span>设置</span>
      </button>
    </nav>
  );
}
