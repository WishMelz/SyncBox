import { test } from 'node:test';
import assert from 'node:assert/strict';
import { SendAttempts } from '../src/lib/send-attempts.ts';

test('manual retries reuse the ID, new content and successful sends do not', () => {
  const attempts = new SendAttempts();
  const first = attempts.get('one', 'text', []);
  assert.equal(attempts.get('one', 'text', []), first);
  assert.notEqual(attempts.get('two', 'text', []), first);
  assert.notEqual(attempts.get('one', 'edited', []), first);
  const edited = attempts.get('one', 'edited', []);
  attempts.clear('one');
  assert.notEqual(attempts.get('one', 'edited', []), edited);
});

test('same-name files are not confused when bytes or selection changes', () => {
  const attempts = new SendAttempts();
  const a = new File(['original'], 'file.txt');
  const b = new File(['modified'], 'file.txt');
  const first = attempts.get('one', '', [a]);
  assert.equal(attempts.get('one', '', [a]), first);
  assert.notEqual(attempts.get('one', '', [b]), first);
});
