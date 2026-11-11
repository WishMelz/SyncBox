export type TextPart = { text: string; href?: string };

/** Only HTTP(S) links are interactive. Everything remains React-rendered text. */
export function splitMessageLinks(text: string): TextPart[] {
  const parts: TextPart[] = [];
  const pattern = /https?:\/\/[^\s<>"'\u3000，。！？；：、）】》」』]+/gi;
  let cursor = 0;
  for (const match of text.matchAll(pattern)) {
    const start = match.index;
    let candidate = match[0].replace(/[.,!?;:，。！？；：、）】》」』]+$/u, '');
    for (const [open, close] of [
      ['(', ')'],
      ['[', ']'],
    ]) {
      while (
        candidate.endsWith(close) &&
        candidate.split(close).length > candidate.split(open).length
      ) {
        candidate = candidate.slice(0, -1);
      }
    }
    let valid = false;
    try {
      const url = new URL(candidate);
      valid = ['http:', 'https:'].includes(url.protocol) && !!url.hostname;
    } catch {
      /* Keep malformed links as plain text. */
    }
    if (!valid) continue;
    if (cursor < start) parts.push({ text: text.slice(cursor, start) });
    parts.push({ text: candidate, href: candidate });
    cursor = start + candidate.length;
  }
  if (cursor < text.length) parts.push({ text: text.slice(cursor) });
  return parts;
}

export function startsMessageDate(current: string, previous?: string): boolean {
  if (!previous) return true;
  return new Date(current).toDateString() !== new Date(previous).toDateString();
}

export function messageDateLabel(value: string, now = new Date()): string {
  const date = new Date(value);
  if (date.toDateString() === now.toDateString()) return '今天';
  const yesterday = new Date(now);
  yesterday.setDate(yesterday.getDate() - 1);
  if (date.toDateString() === yesterday.toDateString()) return '昨天';
  return date.toLocaleDateString('zh-CN', {
    ...(date.getFullYear() !== now.getFullYear() ? { year: 'numeric' as const } : {}),
    month: 'long',
    day: 'numeric',
  });
}
