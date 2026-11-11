import { useRef, type ReactElement } from 'react';
import * as ContextMenu from '@radix-ui/react-context-menu';
import type { MenuAction } from '@/components/ui/action-menu';

export function MessageContextMenu({
  children,
  actions,
  restoreFocus,
}: {
  children: ReactElement;
  actions: MenuAction[];
  restoreFocus: () => void;
}) {
  const pending = useRef<(() => void) | null>(null);
  return (
    <ContextMenu.Root
      onOpenChange={(open) => {
        if (open) pending.current = null;
      }}
    >
      <ContextMenu.Trigger asChild>{children}</ContextMenu.Trigger>
      <ContextMenu.Portal>
        <ContextMenu.Content
          className="conversation-context-menu message-context-menu"
          collisionPadding={8}
          aria-label="消息操作"
          onCloseAutoFocus={(event) => {
            event.preventDefault();
            const action = pending.current;
            pending.current = null;
            restoreFocus();
            // The next dialog must mount after Radix releases its focus scope.
            if (action) window.setTimeout(action, 0);
          }}
        >
          {actions.map((action) => (
            <ContextMenu.Item
              key={action.label}
              disabled={action.disabled}
              className={action.danger ? 'context-danger' : ''}
              onSelect={() => {
                if (action.opensDialog) pending.current = action.onSelect;
                else action.onSelect();
              }}
            >
              {action.icon}
              {action.label}
            </ContextMenu.Item>
          ))}
        </ContextMenu.Content>
      </ContextMenu.Portal>
    </ContextMenu.Root>
  );
}
