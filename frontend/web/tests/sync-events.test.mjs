import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  addSyncEventToBatch,
  createSyncBatch,
  parseSseFrames,
  planSyncActions,
} from '../src/lib/sync-events.ts';

test('parseSseFrames handles LF, CRLF, split chunks, comments, and ignores malformed JSON', () => {
  const chunk1 = ': heartbeat\r\n\r\nevent: sync\r\ndata: {"type":"invalidate","scope":"messages","conversationId":"c1","messageId":"m1"}\r\n\r\nevent: sync\r\ndata: {"type":"invalidate",';
  const r1 = parseSseFrames(chunk1);
  assert.equal(r1.events.length, 1);
  assert.equal(r1.events[0].messageId, 'm1');

  const chunk2 = r1.rest + '"scope":"devices"}\r\n\r\ndata: bad-json\n\n';
  const r2 = parseSseFrames(chunk2);
  assert.equal(r2.events.length, 1);
  assert.equal(r2.events[0].scope, 'devices');
  assert.equal(r2.rest, '');
});

test('planSyncActions routes by scope, conversationId, and messageId without unrelated history loads', () => {
  const batch = createSyncBatch();
  addSyncEventToBatch(batch, {
    type: 'invalidate',
    scope: 'messages',
    conversationId: 'other-conv',
    messageId: 'm-other',
  });
  addSyncEventToBatch(batch, {
    type: 'invalidate',
    scope: 'conversations',
    conversationId: 'other-conv',
  });
  const planUnrelated = planSyncActions(batch, {
    selectedConversationId: 'active-conv',
    isSearchingMessages: false,
    isHistoryReady: true,
    favoritesOpen: false,
    filesOpen: false,
    devicesOpen: false,
    settingsOpen: false,
  });
  assert.equal(planUnrelated.refreshConversations, true);
  assert.deepEqual(planUnrelated.selectedHistory, { type: 'none' });
  assert.equal(planUnrelated.refreshFavorites, false);

  const activeBatch = createSyncBatch();
  addSyncEventToBatch(activeBatch, {
    type: 'invalidate',
    scope: 'messages',
    conversationId: 'active-conv',
    messageId: 'm1',
  });
  const planSingle = planSyncActions(activeBatch, {
    selectedConversationId: 'active-conv',
    isSearchingMessages: false,
    isHistoryReady: true,
    favoritesOpen: false,
    filesOpen: true,
    devicesOpen: false,
    settingsOpen: false,
  });
  assert.deepEqual(planSingle.selectedHistory, { type: 'fetchMessages', messageIds: ['m1'] });
  assert.equal(planSingle.refreshFiles, true);

  const searchPlan = planSyncActions(activeBatch, {
    selectedConversationId: 'active-conv',
    isSearchingMessages: true,
    isHistoryReady: true,
    favoritesOpen: false,
    filesOpen: false,
    devicesOpen: false,
    settingsOpen: false,
  });
  assert.deepEqual(searchPlan.selectedHistory, { type: 'refreshLatest' });
});
