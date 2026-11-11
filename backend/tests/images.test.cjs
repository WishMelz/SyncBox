const { test } = require('node:test');
const assert = require('node:assert/strict');
const { NestFactory } = require('@nestjs/core');
const { ExpressAdapter } = require('@nestjs/platform-express');
const { DataSource } = require('typeorm');
const request = require('supertest');
const sharp = require('sharp');
process.env.DATABASE_PATH = ':memory:';
process.env.NODE_ENV = 'test';
const { AppModule } = require('../dist/app.module');
const { configureApp } = require('../dist/app.setup');

test('image messages validate bytes, require auth, persist and cascade with messages/conversations', async (t) => {
  const app = await NestFactory.create(AppModule, new ExpressAdapter(), { logger: false });
  t.after(() => app.close());
  configureApp(app);
  await app.init();
  const api = request(app.getHttpServer());
  const db = app.get(DataSource);
  const login = await api
    .post('/api/v1/auth/setup')
    .send({ username: 'image-test', password: '123456' })
    .expect(201);
  const auth = { Authorization: `Bearer ${login.body.accessToken}` };
  const c = await api.post('/api/v1/conversations').set(auth).send({ title: 'Images' }).expect(201);
  const path = `/api/v1/conversations/${c.body.id}/images`;
  const png = await sharp({ create: { width: 32, height: 24, channels: 3, background: '#8568ff' } })
    .png()
    .toBuffer();
  await api.post(path).attach('image', png, 'test.png').expect(401);
  await api.post(path).set(auth).send({ content: 'missing image' }).expect(400);
  await api
    .post(path)
    .set(auth)
    .attach(
      'image',
      Buffer.from('<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>'),
      { filename: 'fake.png', contentType: 'image/png' },
    )
    .expect(400);
  await api
    .post(path)
    .set(auth)
    .attach('image', Buffer.alloc(8 * 1024 * 1024 + 1), 'large.png')
    .expect(413);
  await api
    .post(path)
    .set(auth)
    .attach('image', png, 'one.png')
    .attach('image', png, 'two.png')
    .expect(400);
  await api
    .post('/api/v1/conversations/00000000-0000-4000-8000-000000000000/images')
    .set(auth)
    .attach('image', png, 'missing.png')
    .expect(404);
  const sent = await api
    .post(path)
    .set(auth)
    .field('content', '截图注释')
    .attach('image', png, 'image.png')
    .expect(201);
  assert.equal(sent.body.content, '截图注释');
  assert.equal(sent.body.image.mimeType, 'image/webp');
  assert.equal(sent.body.image.width, 32);
  assert.equal(sent.body.image.height, 24);
  const imagePath = `/api/v1/messages/${sent.body.id}/image`;
  await api.get(imagePath).expect(401);
  const binary = await api
    .get(imagePath)
    .set(auth)
    .expect(200)
    .expect('Content-Type', /image\/webp/)
    .expect('X-Content-Type-Options', 'nosniff')
    .expect('Cache-Control', 'no-store');
  assert.equal((await sharp(binary.body).metadata()).width, 32);
  const history = await api
    .get(`/api/v1/conversations/${c.body.id}/messages?q=${encodeURIComponent('截图')}`)
    .set(auth)
    .expect(200);
  assert.equal(history.body.items[0].image.size, binary.body.length);
  const legacy = await api.get('/api/v1/messages').set(auth).expect(200);
  assert.equal(legacy.body.items[0].image.mimeType, 'image/webp');
  assert.equal('data' in legacy.body.items[0], false);
  const detail = await api.get(`/api/v1/messages/${sent.body.id}`).set(auth).expect(200);
  assert.deepEqual(detail.body.image, sent.body.image);
  await api.delete(`/api/v1/messages/${sent.body.id}`).set(auth).expect(204);
  await api.get(imagePath).set(auth).expect(404);
  assert.equal((await db.query('SELECT COUNT(*) AS n FROM message_images'))[0].n, 0);
  const second = await api.post(path).set(auth).attach('image', png, 'no-caption.png').expect(201);
  assert.equal(second.body.content, '[图片]');
  const plain = await api
    .post(`/api/v1/conversations/${c.body.id}/messages`)
    .set(auth)
    .send({ content: 'ordinary text' })
    .expect(201);
  assert.equal(plain.body.image, null);
  await api.get(`/api/v1/messages/${plain.body.id}/image`).set(auth).expect(404);
  await api.delete(`/api/v1/conversations/${c.body.id}`).set(auth).expect(204);
  assert.equal((await db.query('SELECT COUNT(*) AS n FROM message_images'))[0].n, 0);
});
