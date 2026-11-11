/** Copy on HTTPS and on private-network HTTP, keeping the user's focus/selection. */
export async function copyText(text: string): Promise<void> {
  if (navigator.clipboard?.writeText) {
    try {
      await navigator.clipboard.writeText(text);
      return;
    } catch {
      // HTTP deployments and denied clipboard permission can use the legacy action.
    }
  }
  const previousFocus = document.activeElement as HTMLElement | null;
  const selection = window.getSelection();
  const ranges = selection
    ? Array.from({ length: selection.rangeCount }, (_, i) => selection.getRangeAt(i).cloneRange())
    : [];
  const field = document.createElement('textarea');
  field.value = text;
  field.readOnly = true;
  field.style.cssText = 'position:fixed;left:-9999px;top:0;opacity:0;pointer-events:none';
  // Keep the temporary selection inside an active focus trap (for example a
  // message menu); otherwise Radix immediately moves focus away from the field.
  const scope = previousFocus?.closest('[role="menu"], [role="dialog"], dialog');
  (scope ?? document.body).appendChild(field);
  try {
    field.focus({ preventScroll: true });
    field.select();
    if (!document.execCommand('copy')) throw new Error('复制失败');
  } finally {
    field.remove();
    previousFocus?.focus({ preventScroll: true });
    selection?.removeAllRanges();
    ranges.forEach((range) => selection?.addRange(range));
  }
}
