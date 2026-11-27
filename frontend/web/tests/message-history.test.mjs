import { test } from 'node:test';
import assert from 'node:assert/strict';
import { MessageHistory, messageCursor } from '../src/lib/message-history.ts';

function fixture() {
  const state = { messages: Array.from({ length: 9 }, (_, n) => ({ id: String(n).padStart(3, '0'), createdAt: '2026-11-09T00:00:00.000Z', content: `${n}` })), calls: [], fail: false };
  const history = new MessageHistory(async (options) => {
    state.calls.push(options);
    if (state.fail) throw new Error('offline');
    const items = state.messages.filter((m) => (!options.before || messageCursor(m) < options.before) && (!options.since || messageCursor(m) >= options.since)).reverse();
    return { items: items.slice(0, 3), total: state.messages.length, page: 1, totalPages: 3, hasMore: items.length > 3, nextCursor: items.length > 3 ? messageCursor(items[2]) : null };
  });
  return { state, history };
}
test('cursor history survives insertion, deletion of the cursor message, and metadata updates', async () => {
  const { state, history } = fixture();
  await history.refresh();
  assert.deepEqual(history.state.data.items.map((m) => m.id), ['008', '007', '006']);
  state.messages = state.messages.filter((m) => m.id !== '006');
  state.messages.push({ id: '009', createdAt: '2026-11-09T00:00:00.000Z', content: 'new' });
  await history.loadOlder();
  assert.deepEqual(history.state.data.items.map((m) => m.id), ['008', '007', '006', '005', '004', '003']);
  state.messages.find((m) => m.id === '004').annotation = 'updated';
  await history.refresh();
  assert.deepEqual(history.state.data.items.map((m) => m.id), ['009', '008', '007', '005', '004', '003']);
  assert.equal(history.state.data.items.find((m) => m.id === '004').annotation, 'updated');
  await history.loadOlder();
  assert.equal(history.state.hasOlder, false);
  assert.equal(new Set(history.state.data.items.map((m) => m.id)).size, 9);
});
test('failed older load keeps content and cursor, then manual retry succeeds', async () => {
  const { state, history } = fixture();
  await history.refresh();
  const previous = history.state.data;
  state.fail = true;
  await assert.rejects(history.loadOlder(), /offline/);
  assert.equal(history.state.data, previous);
  assert.equal(history.state.loadingOlder, false);
  state.fail = false;
  await history.loadOlder();
  assert.equal(history.state.data.items.length, 6);
  assert.equal(history.state.olderError, null);
});
test('duplicate older requests coalesce and live refresh runs after older loads', async () => {
  const { state, history } = fixture();
  await history.refresh();
  await Promise.all([history.loadOlder(), history.loadOlder(), history.refresh()]);
  assert.equal(state.calls.filter((o) => o.before && !o.since).length, 1);
  assert.equal(history.state.data.items.length, 6);
});
test('sending preserves loaded history, while cold conversation refreshes its latest messages', async () => {
  const { state, history } = fixture();
  const sent = { id: '009', createdAt: '2026-11-09T00:00:00.000Z', content: 'sent' };
  state.messages.push(sent);
  history.sent(sent);
  await history.refresh();
  assert.equal(history.state.data.items.length, 3);
  await history.loadOlder();
  history.sent({ ...sent, id: '010' });
  assert.equal(history.state.data.items.length, 7);
});

test('refreshLatest fetches only 1 page even when multiple older pages are loaded, and upsert/remove patch locally', async () => {
  const { state, history } = fixture();
  await history.refresh();
  await history.loadOlder();
  await history.loadOlder();
  assert.equal(history.state.data.items.length, 9);
  assert.ok(state.calls.some((c) => c.before && c.includeTotal === false));

  const callsBefore = state.calls.length;
  // Delete message 007 (on page 1) and add 009 while page 2 & 3 stay loaded.
  state.messages = state.messages.filter((m) => m.id !== '007');
  state.messages.push({ id: '009', createdAt: '2026-11-09T00:00:00.000Z', content: 'new' });
  await history.refreshLatest();
  assert.equal(state.calls.length - callsBefore, 1, 'refreshLatest must make only 1 fetchPage call');
  assert.deepEqual(
    history.state.data.items.map((m) => m.id),
    ['009', '008', '006', '005', '004', '003', '002', '001', '000'],
  );

  history.upsertMessage({ id: '010', createdAt: '2026-11-09T00:00:00.000Z', content: 'patched' });
  assert.equal(history.state.data.items[0].id, '010');
  assert.equal(history.state.data.total, 10);

  history.removeMessage('007'); // no-op for absent message
  assert.equal(history.state.data.total, 10);

  history.removeMessage('010');
  assert.equal(history.state.data.items[0].id, '009');
  assert.equal(history.state.data.total, 9);
});
