export type HighlightRange = { start: number; end: number };
export type HighlightPart = { text: string; highlighted: boolean };

// Map each folded UTF-16 position back to the complete original code point.
// Lowercase expansions (for example İ → i + combining dot) must not shift slices.
function fold(text: string) {
  let value = '';
  const starts: number[] = [],
    ends: number[] = [];
  let offset = 0;
  for (const char of text) {
    const lowered = char.toLowerCase().replaceAll('ς', 'σ');
    value += lowered;
    for (let i = 0; i < lowered.length; i++) {
      starts.push(offset);
      ends.push(offset + char.length);
    }
    offset += char.length;
  }
  return { value, starts, ends };
}

/** Case-insensitive literal substring ranges; never interpolate user input into regex. */
export function findHighlightRanges(text: string, query: string): HighlightRange[] {
  const needle = fold(query.trim()).value;
  if (!needle) return [];
  const haystack = fold(text);
  const ranges: HighlightRange[] = [];
  let cursor = 0;
  while (cursor < haystack.value.length) {
    const at = haystack.value.indexOf(needle, cursor);
    if (at < 0) break;
    const next = { start: haystack.starts[at], end: haystack.ends[at + needle.length - 1] };
    const previous = ranges.at(-1);
    if (previous && next.start <= previous.end) previous.end = Math.max(previous.end, next.end);
    else ranges.push(next);
    cursor = at + needle.length;
  }
  return ranges;
}

export function splitHighlight(
  text: string,
  query: string,
  ranges = findHighlightRanges(text, query),
): HighlightPart[] {
  const parts: HighlightPart[] = [];
  let cursor = 0;
  for (const { start, end } of ranges) {
    if (start > cursor) parts.push({ text: text.slice(cursor, start), highlighted: false });
    parts.push({ text: text.slice(start, end), highlighted: true });
    cursor = end;
  }
  if (cursor < text.length || !parts.length)
    parts.push({ text: text.slice(cursor), highlighted: false });
  return parts;
}

/** Project full-message matches onto a link/plain-text segment without altering href. */
export function sliceHighlightRanges(
  ranges: HighlightRange[],
  offset: number,
  length: number,
): HighlightRange[] {
  return ranges
    .filter((range) => range.start < offset + length && range.end > offset)
    .map((range) => ({
      start: Math.max(0, range.start - offset),
      end: Math.min(length, range.end - offset),
    }));
}
