import * as DropdownMenu from '@radix-ui/react-dropdown-menu';
import { FolderOpen, ImagePlus, Paperclip } from 'lucide-react';

export function AttachmentMenu({
  disabled,
  onFiles,
  onImages,
}: {
  disabled: boolean;
  onFiles: () => void;
  onImages: () => void;
}) {
  return (
    <DropdownMenu.Root>
      <DropdownMenu.Trigger asChild>
        <button
          type="button"
          className="icon-btn composer-attach"
          aria-label="添加附件"
          title="添加图片或文件"
          disabled={disabled}
        >
          <Paperclip size={23} />
        </button>
      </DropdownMenu.Trigger>
      <DropdownMenu.Portal>
        <DropdownMenu.Content
          className="conversation-context-menu attachment-menu"
          side="top"
          align="start"
          sideOffset={12}
          collisionPadding={12}
        >
          <DropdownMenu.Item onSelect={onImages}>
            <ImagePlus size={20} />
            图片
          </DropdownMenu.Item>
          <DropdownMenu.Item onSelect={onFiles}>
            <FolderOpen size={20} />
            文件
          </DropdownMenu.Item>
          <DropdownMenu.Separator />
          <p className="attachment-menu-hint">最多 5 个文件，合计 20 MB</p>
        </DropdownMenu.Content>
      </DropdownMenu.Portal>
    </DropdownMenu.Root>
  );
}
