import { useEffect, useRef, type ReactNode } from 'react';
import { Button } from './button';

export function ConfirmDialog({
  title,
  children,
  onCancel,
  onConfirm,
}: {
  title: string;
  children: ReactNode;
  onCancel: () => void;
  onConfirm: () => void;
}) {
  const ref = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    const before = document.activeElement as HTMLElement | null;
    const dialog = ref.current!;
    dialog.showModal();
    return () => {
      dialog.close();
      before?.focus();
    };
  }, []);
  return (
    <dialog
      ref={ref}
      className="confirm-dialog"
      aria-labelledby="confirm-title"
      onKeyDown={(event) => event.stopPropagation()}
      onCancel={(e) => {
        e.preventDefault();
        onCancel();
      }}
    >
      <h2 id="confirm-title">{title}</h2>
      <p>{children}</p>
      <footer>
        <Button autoFocus variant="outline" onClick={onCancel}>
          取消
        </Button>
        <Button variant="destructive" onClick={onConfirm}>
          确认删除
        </Button>
      </footer>
    </dialog>
  );
}
