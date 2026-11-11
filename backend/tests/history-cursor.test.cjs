const { test } = require('node:test');
const assert = require('node:assert/strict');
const { NestFactory } = require('@nestjs/core');
const { ExpressAdapter } = require('@nestjs/platform-express');
const { DataSource } = require('typeorm');
const request = require('supertest');
process.env.DATABASE_PATH = ':memory:';
process.env.NODE_ENV = 'test';
const { AppModule } = require('../dist/app.module');
const { configureApp } = require('../dist/app.setup');

test('stable history cursors, refresh range, legacy pages and validation', async (t) => {
  const app = await NestFactory.create(AppModule, new ExpressAdapter(), { logger: false });
  t.after(() => app.close());
  configureApp(app);
  await app.init();
  const api = request(app.getHttpServer()), db = app.get(DataSource);
  const auth = { Authorization: 'Bearer ' + (await api.post('/api/v1/auth/setup').send({ username: 'cursor', password: 'cursor123' }).expect(201)).body.accessToken };
  const conversation = (await api.post('/api/v1/conversations').set(auth).send({ title: 'history' }).expect(201)).body;
  const path = `/api/v1/conversations/${conversation.id}/messages`;
  const messages = [];
  for (let n = 0; n < 9; n++) messages.push((await api.post(path).set(auth).send({ content: `history ${n}` }).expect(201)).body);
  await db.query('UPDATE messages SET created_at=? WHERE conversation_id=?', ['2026-11-09T00:00:00.000Z', conversation.id]);
  const sorted = messages.map((m) => m.id).sort().reverse();
  const read = async (query) => (await api.get(path).set(auth).query({ pageSize: 3, ...query }).expect(200)).body;
  const first = await read({});
  assert.deepEqual(first.items.map((m) => m.id), sorted.slice(0, 3));
  assert.equal(first.hasMore, true);
  const legacy = await read({ page: 2 });
  assert.deepEqual(legacy.items.map((m) => m.id), sorted.slice(3, 6));
  await api.delete(`/api/v1/messages/${sorted[2]}`).set(auth).expect(204);
  const fresh = (await api.post(path).set(auth).send({ content: 'newest' }).expect(201)).body;
  const second = await read({ before: first.nextCursor });
  assert.deepEqual(second.items.map((m) => m.id), sorted.slice(3, 6));
  assert.equal(second.total, 9);
  const third = await read({ before: second.nextCursor });
  assert.deepEqual(third.items.map((m) => m.id), sorted.slice(6));
  assert.equal(third.hasMore, false);
  assert.equal(third.nextCursor, null);
  const since = `${second.items.at(-1).createdAt}|${second.items.at(-1).id}`;
  let page = await read({ since }), refreshed = [...page.items];
  while (page.hasMore) {
    page = await read({ since, before: page.nextCursor });
    refreshed.push(...page.items);
  }
  assert.deepEqual(refreshed.map((m) => m.id), [fresh.id, ...sorted.slice(0, 6).filter((id) => id !== sorted[2])]);
  await api.get(path).query({ before: first.nextCursor }).expect(401);
  for (const before of ['garbage', '2026-99-99T00:00:00.000Z|00000000-0000-4000-8000-000000000000', "' OR 1=1 --", 'x'.repeat(101)]) {
    await api.get(path).set(auth).query({ before }).expect(400);
  }
  await api.get(path).set(auth).query({ page: 2, before: first.nextCursor }).expect(400);
  const searched = await read({ q: 'newest' });
  assert.deepEqual(searched.items.map((m) => m.id), [fresh.id]);
});
