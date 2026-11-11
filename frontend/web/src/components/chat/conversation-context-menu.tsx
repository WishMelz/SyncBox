import { useRef, type ReactElement } from 'react';
import * as ContextMenu from '@radix-ui/react-context-menu';
import { Pencil, Pin, PinOff, Trash2 } from 'lucide-react';
import type { Conversation } from '@/services/conversations';

export function ConversationContextMenu({
  conversation,
  disabled,
  children,
  onPin,
  onRename,
  onDelete,
}: {
  conversation: Conversation;
  disabled: boolean;
  children: ReactElement;
  onPin: () => void;
  onRename: () => void;
  onDelete: () => void;
}) {
  const dialogAction = useRef<(() => void) | null>(null);
  return (
    <ContextMenu.Root
      onOpenChange={(open) => {
        if (open) dialogAction.current = null;
      }}
    >
      <ContextMenu.Trigger asChild>{children}</ContextMenu.Trigger>
      <ContextMenu.Portal>
        <ContextMenu.Content
          className="conversation-context-menu"
          collisionPadding={8}
          onCloseAutoFocus={(event) => {
            const action = dialogAction.current;
            if (!action) return;
            event.preventDefault();
            dialogAction.current = null;
            // Open after the menu focus trap has unmounted so the dialog can focus its input.
            window.setTimeout(action, 0);
          }}
          aria-label={`会话操作：${conversation.title}`}
        >
          <ContextMenu.Item disabled={disabled} onSelect={onPin}>
            {conversation.isPinned ? <PinOff size={15} /> : <Pin size={15} />}
            {conversation.isPinned ? '取消置顶' : '置顶'}
          </ContextMenu.Item>
          <ContextMenu.Item
            disabled={disabled}
            onSelect={() => {
              dialogAction.current = onRename;
            }}
          >
            <Pencil size={15} />
            改名
          </ContextMenu.Item>
          <ContextMenu.Separator />
          <ContextMenu.Item
            disabled={disabled}
            onSelect={() => {
              dialogAction.current = onDelete;
            }}
            className="context-danger"
          >
            <Trash2 size={15} />
            删除
          </ContextMenu.Item>
        </ContextMenu.Content>
      </ContextMenu.Portal>
    </ContextMenu.Root>
  );
}
