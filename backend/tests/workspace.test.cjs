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
test('pin ordering persists, device rename is validated, and favorites return full searchable paged content', async (t) => {
  const app = await NestFactory.create(AppModule, new ExpressAdapter(), { logger: false });
  t.after(() => app.close());
  configureApp(app);
  await app.init();
  const api = request(app.getHttpServer()),
    db = app.get(DataSource);
  const login = { username: 'workspace', password: 'Workspace-2026' };
  const session = (await api.post('/api/v1/auth/setup').send(login).expect(201)).body;
  const auth = { Authorization: `Bearer ${session.accessToken}` };
  const device = (
    await api.post('/api/v1/devices').set(auth).send({ name: 'Web', platform: 'web' }).expect(201)
  ).body;
  await api.post('/api/v1/devices/heartbeat').set(auth).expect(204);
  const listedDevice = (await api.get('/api/v1/devices').set(auth).expect(200)).body[0];
  assert.equal(listedDevice.id, device.id);
  assert.equal(listedDevice.online, true);
  await api.patch(`/api/v1/devices/${device.id}`).send({ name: 'Mac' }).expect(401);
  for (const name of ['', '  ', null, 'a'.repeat(81)])
    await api.patch(`/api/v1/devices/${device.id}`).set(auth).send({ name }).expect(400);
  const renamed = (
    await api
      .patch(`/api/v1/devices/${device.id}`)
      .set(auth)
      .send({ name: '  我的电脑  ' })
      .expect(200)
  ).body;
  assert.equal(renamed.name, '我的电脑');
  await api
    .patch('/api/v1/devices/00000000-0000-4000-8000-000000000000')
    .set(auth)
    .send({ name: 'other' })
    .expect(404);
  const old = (
    await api.post('/api/v1/conversations').set(auth).send({ title: '旧会话' }).expect(201)
  ).body;
  const newer = (
    await api.post('/api/v1/conversations').set(auth).send({ title: '新会话' }).expect(201)
  ).body;
  await db.query('UPDATE conversations SET updated_at=? WHERE id=?', [
    '2020-01-01T00:00:00.000Z',
    old.id,
  ]);
  await api.patch(`/api/v1/conversations/${old.id}`).send({ pinned: true }).expect(401);
  for (const pinned of [null, 'true', 1])
    await api.patch(`/api/v1/conversations/${old.id}`).set(auth).send({ pinned }).expect(400);
  const pin = (
    await api.patch(`/api/v1/conversations/${old.id}`).set(auth).send({ pinned: true }).expect(200)
  ).body;
  assert.equal(pin.isPinned, true);
  assert.equal(pin.updatedAt, '2020-01-01T00:00:00.000Z');
  let list = (await api.get('/api/v1/conversations?pageSize=1').set(auth).expect(200)).body;
  assert.equal(list.items[0].id, old.id);
  assert.equal(list.items[0].isPinned, true);
  await api
    .patch(`/api/v1/conversations/${old.id}`)
    .set(auth)
    .send({ title: '置顶资料' })
    .expect(200);
  assert.equal((await api.get(`/api/v1/conversations/${old.id}`).set(auth)).body.isPinned, true);
  const long = '收藏全文'.repeat(200);
  const message = (
    await api
      .post(`/api/v1/conversations/${old.id}/messages`)
      .set(auth)
      .send({ content: long })
      .expect(201)
  ).body;
  const unread = (await api.get('/api/v1/conversations').set(auth).expect(200)).body.items.find((item) => item.id === old.id);
  assert.equal(unread.unreadCount, 1);
  await api.patch(`/api/v1/conversations/${old.id}/read`).set(auth).expect(204);
  const read = (await api.get('/api/v1/conversations').set(auth).expect(200)).body.items.find((item) => item.id === old.id);
  assert.equal(read.unreadCount, 0);
  assert.equal(message.senderDevice.name, '我的电脑');
  const attachment = (
    await api
      .post(`/api/v1/conversations/${newer.id}/attachments`)
      .set(auth)
      .attach('files', Buffer.from('report'), '100%_report.txt')
      .expect(201)
  ).body;
  const files = (await api.get('/api/v1/messages/files').set(auth).expect(200)).body;
  assert.equal(files.total, 1);
  assert.equal(files.items[0].kind, 'attachment');
  assert.equal(files.items[0].name, '100%_report.txt');
  assert.equal(files.items[0].conversationId, newer.id);
  const matchingFiles = (
    await api
      .get('/api/v1/messages/files?q=' + encodeURIComponent('report'))
      .set(auth)
      .expect(200)
  ).body;
  assert.equal(matchingFiles.total, 1);
  await api.patch(`/api/v1/messages/${message.id}`).set(auth).send({ isStarred: true }).expect(200);
  await api
    .patch(`/api/v1/messages/${attachment.id}`)
    .set(auth)
    .send({ isStarred: true })
    .expect(200);
  await api
    .post(`/api/v1/conversations/${newer.id}/messages`)
    .set(auth)
    .send({ content: '不收藏' })
    .expect(201);
  await api.get('/api/v1/messages/starred').expect(401);
  const favorites = (await api.get('/api/v1/messages/starred?pageSize=1').set(auth).expect(200))
    .body;
  assert.equal(favorites.total, 2);
  assert.equal(favorites.totalPages, 2);
  const text = (
    await api
      .get('/api/v1/messages/starred?q=' + encodeURIComponent('收藏全文'))
      .set(auth)
      .expect(200)
  ).body;
  assert.equal(text.items[0].content, long);
  assert.equal(text.items[0].conversationId, old.id);
  assert.equal(text.items[0].conversationTitle, '置顶资料');
  await api
    .patch(`/api/v1/conversations/${old.id}`)
    .set(auth)
    .send({ title: '收藏来源已改名' })
    .expect(200);
  const updatedFavorites = (await api.get('/api/v1/messages/starred').set(auth).expect(200)).body;
  assert.equal(
    updatedFavorites.items.find((m) => m.id === message.id).conversationTitle,
    '收藏来源已改名',
  );
  const file = (await api.get('/api/v1/messages/starred?q=100%25_').set(auth).expect(200)).body;
  assert.equal(file.items[0].attachments[0].name, '100%_report.txt');
  const second = (await api.post('/api/v1/auth/login').send(login).expect(200)).body;
  assert.equal(
    (await api.get('/api/v1/conversations').set({ Authorization: `Bearer ${second.accessToken}` }))
      .body.items[0].id,
    old.id,
  );
  await api.patch(`/api/v1/conversations/${old.id}`).set(auth).send({ pinned: false }).expect(200);
  await api
    .patch(`/api/v1/messages/${message.id}`)
    .set(auth)
    .send({ isStarred: false })
    .expect(200);
  assert.equal((await api.get('/api/v1/messages/starred').set(auth)).body.total, 1);
  assert.equal((await api.get('/api/v1/devices').set(auth)).body[0].name, '我的电脑');
});
