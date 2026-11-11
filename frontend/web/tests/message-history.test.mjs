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
