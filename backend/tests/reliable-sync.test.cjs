const { test } = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const { NestFactory } = require('@nestjs/core');
const request = require('supertest');
const { ExpressAdapter } = require('@nestjs/platform-express');
const sharp = require('sharp');
process.env.DATABASE_PATH = ':memory:';
process.env.NODE_ENV = 'test';
const { AppModule } = require('../dist/app.module');
const { configureApp } = require('../dist/app.setup');

test('text, image and five-file sends keep a single message on retry with clientId', async (t) => {
  const app = await NestFactory.create(AppModule, new ExpressAdapter(), { logger: false });
  t.after(() => app.close());
  configureApp(app);
  await app.init();
  const api = request(app.getHttpServer());
  const session = await api.post('/api/v1/auth/setup').send({ username: 'retry-test', password: '123456' }).expect(201);
  const auth = { Authorization: `Bearer ${session.body.accessToken}` };
  const conversation = await api.post('/api/v1/conversations').set(auth).send({ title: 'Retry' }).expect(201);
  const path = `/api/v1/conversations/${conversation.body.id}`;
  const textId = randomUUID();
  const sendText = () => api.post(`${path}/messages`).set(auth).send({ content: 'send once', clientId: textId }).expect(201);
  const [first, retry] = await Promise.all([sendText(), sendText()]);
  assert.equal(first.body.id, retry.body.id);
  const image = await sharp({ create: { width: 8, height: 8, channels: 3, background: '#123456' } }).png().toBuffer();
  const imageId = randomUUID();
  const sendImage = () => api.post(`${path}/images`).set(auth).field('content', 'image').field('clientId', imageId).attach('image', image, 'image.png').expect(201);
  assert.equal((await sendImage()).body.id, (await sendImage()).body.id);
  const filesId = randomUUID();
  function sendFiles() {
    let req = api.post(`${path}/attachments`).set(auth).field('content', 'files').field('names', JSON.stringify(['1.txt', '2.txt', '3.txt', '4.txt', '5.txt'])).field('clientId', filesId);
    for (let i = 0; i < 5; i++) req = req.attach('files', Buffer.from(`content ${i}`), 'upload');
    return req.expect(201);
  }
  const files = await sendFiles();
  assert.equal(files.body.attachments.length, 5);
  assert.deepEqual((await sendFiles()).body.attachments, files.body.attachments);
  const history = await api.get(`${path}/messages`).set(auth).expect(200);
  assert.equal(history.body.total, 3);
  await api.post(`${path}/attachments`).set(auth).field('clientId', 'not-a-uuid').attach('files', Buffer.from('x'), 'x.txt').expect(400);
  await api.post(`${path}/images`).set(auth).field('clientId', 'not-a-uuid').attach('image', image, 'image.png').expect(400);
  const list = await api.get('/api/v1/conversations').set(auth).expect(200);
  assert.equal(list.body.items[0].unreadCount, 3);
  await api.patch(`${path}/read`).set(auth).expect(204);
  assert.equal((await api.get('/api/v1/conversations').set(auth)).body.items[0].unreadCount, 0);
});

test('authenticated SSE sends invalidation metadata after a write', { timeout: 10000 }, async (t) => {
  const app = await NestFactory.create(AppModule, new ExpressAdapter(), { logger: false });
  configureApp(app);
  await app.listen(0, '127.0.0.1');
  const api = request(app.getHttpServer());
  const controller = new AbortController();
  t.after(async () => { controller.abort(); app.getHttpServer().closeAllConnections(); await app.close(); });
  const session = await api.post('/api/v1/auth/setup').send({ username: 'events-test', password: '123456' }).expect(201);
  const headers = { Authorization: `Bearer ${session.body.accessToken}` };
  await api.get('/api/v1/events').expect(401);
  const stream = await fetch(`${await app.getUrl()}/api/v1/events`, { headers, signal: AbortSignal.any([controller.signal, AbortSignal.timeout(5000)]) });
  assert.match(stream.headers.get('content-type'), /^text\/event-stream/);
  const c = await api.post('/api/v1/conversations').set(headers).send({ title: 'Private title' }).expect(201);
  const reader = stream.body.getReader();
  let text = '';
  while (!text.includes(c.body.id)) {
    const chunk = await reader.read();
    assert.equal(chunk.done, false);
    text += new TextDecoder().decode(chunk.value);
  }
  assert.match(text, /event: sync/);
  assert.match(text, /"scope":"conversations"/);
  assert.ok(!text.includes('Private title'));
  await reader.cancel();
});
