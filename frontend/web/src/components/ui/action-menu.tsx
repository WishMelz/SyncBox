import { useRef, type ReactNode } from 'react';
import * as DropdownMenu from '@radix-ui/react-dropdown-menu';
import { MoreHorizontal } from 'lucide-react';

export interface MenuAction {
  label: string;
  icon: ReactNode;
  onSelect: () => void;
  disabled?: boolean;
  danger?: boolean;
  opensDialog?: boolean;
}
export function ActionMenu({
  label,
  actions,
  disabled = false,
}: {
  label: string;
  actions: MenuAction[];
  disabled?: boolean;
}) {
  const pending = useRef<(() => void) | null>(null);
  return (
    <DropdownMenu.Root
      onOpenChange={(open) => {
        if (open) pending.current = null;
      }}
    >
      <DropdownMenu.Trigger asChild>
        <button
          type="button"
          className="icon-btn more-trigger"
          aria-label={label}
          title={label}
          disabled={disabled}
        >
          <MoreHorizontal size={18} />
        </button>
      </DropdownMenu.Trigger>
      <DropdownMenu.Portal>
        <DropdownMenu.Content
          className="conversation-context-menu action-menu"
          align="end"
          sideOffset={5}
          collisionPadding={8}
          onCloseAutoFocus={(event) => {
            if (!pending.current) return;
            event.preventDefault();
            const action = pending.current;
            pending.current = null;
            window.setTimeout(action, 0);
          }}
        >
          {actions.map((action) => (
            <DropdownMenu.Item
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
            </DropdownMenu.Item>
          ))}
        </DropdownMenu.Content>
      </DropdownMenu.Portal>
    </DropdownMenu.Root>
  );
}
