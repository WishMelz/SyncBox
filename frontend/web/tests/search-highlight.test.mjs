import { test } from 'node:test';
import assert from 'node:assert/strict';
import { findHighlightRanges, splitHighlight } from '../src/lib/search-highlight.ts';
test('literal unicode case-insensitive highlights', () => {
  assert.deepEqual(findHighlightRanges('你好 SyncBox', 'syncbox'), [{ start: 3, end: 10 }]);
  assert.deepEqual(
    splitHighlight('abc [x]', '[x]')
      .filter((x) => x.highlighted)
      .map((x) => x.text),
    ['[x]'],
  );
});
test('empty query has no matches', () => assert.deepEqual(findHighlightRanges('abc', '  '), []));
test('Unicode lowercase expansion does not shift later original-text indexes', () => {
  assert.deepEqual(findHighlightRanges('İ中文 ABC 😀', 'abc'), [{ start: 4, end: 7 }]);
  assert.deepEqual(
    splitHighlight('İ中文 ABC 😀', 'i')
      .filter((x) => x.highlighted)
      .map((x) => x.text),
    ['İ'],
  );
  assert.deepEqual(
    splitHighlight('İ中文 ABC 😀', '😀')
      .filter((x) => x.highlighted)
      .map((x) => x.text),
    ['😀'],
  );
});
test('range slicing preserves a match crossing plain text and a URL', async () => {
  const { sliceHighlightRanges } = await import('../src/lib/search-highlight.ts');
  const text = '打开 https://example.com';
  const ranges = findHighlightRanges(text, '打开 https');
  assert.deepEqual(sliceHighlightRanges(ranges, 0, 3), [{ start: 0, end: 3 }]);
  assert.deepEqual(sliceHighlightRanges(ranges, 3, 19), [{ start: 0, end: 5 }]);
});
test('symbols are literal and case matching preserves original content', () => {
  const text = 'ABC <b>内容</b> .* ABC';
  const parts = splitHighlight(text, ' abc ');
  assert.equal(parts.map((p) => p.text).join(''), text);
  assert.deepEqual(
    parts.filter((p) => p.highlighted).map((p) => p.text),
    ['ABC', 'ABC'],
  );
  assert.deepEqual(
    splitHighlight(text, '.*')
      .filter((p) => p.highlighted)
      .map((p) => p.text),
    ['.*'],
  );
});
