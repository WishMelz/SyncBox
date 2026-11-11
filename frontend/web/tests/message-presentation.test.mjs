import { test } from 'node:test';
import assert from 'node:assert/strict';
import { splitMessageLinks, startsMessageDate, messageDateLabel } from '../src/lib/message-presentation.ts';

test('links preserve all original text and exclude sentence punctuation', () => {
  const text = '文档 https://example.com/a(b)。以及 (http://192.168.1.2:3000/path).';
  const parts = splitMessageLinks(text);
  assert.equal(parts.map((p) => p.text).join(''), text);
  assert.deepEqual(parts.filter((p) => p.href).map((p) => p.href), [
    'https://example.com/a(b)', 'http://192.168.1.2:3000/path',
  ]);
});

test('only HTTP(S) links are interactive and HTML stays plain text', () => {
  const text = '<script>alert(1)</script> javascript:alert(1) data:text/html,hi ftp://host https://example.com?q=<img>';
  const parts = splitMessageLinks(text);
  assert.equal(parts.map((p) => p.text).join(''), text);
  assert.deepEqual(parts.filter((p) => p.href).map((p) => p.href), ['https://example.com?q=']);
});

test('date sections change on local midnight, not message gaps', () => {
  assert.equal(startsMessageDate('2026-11-09T23:59:00', '2026-11-09T01:00:00'), false);
  assert.equal(startsMessageDate('2026-11-10T00:01:00', '2026-11-09T23:59:00'), true);
  assert.equal(startsMessageDate('2026-11-10T00:01:00'), true);
  assert.equal(messageDateLabel('2026-11-09T15:00:00', new Date('2026-11-09T16:00:00')), '今天');
  assert.equal(messageDateLabel('2026-11-08T15:00:00', new Date('2026-11-09T16:00:00')), '昨天');
});
