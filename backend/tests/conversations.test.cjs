const { test } = require('node:test');
const assert = require('node:assert/strict');
const { NestFactory } = require('@nestjs/core');
const { ExpressAdapter } = require('@nestjs/platform-express');
const request = require('supertest');
process.env.DATABASE_PATH = ':memory:';
process.env.NODE_ENV = 'test';
const { AppModule } = require('../dist/app.module');
const { configureApp } = require('../dist/app.setup');
test('conversation lifecycle, message search, sharing and ownership', async (t) => {
  const app = await NestFactory.create(AppModule, new ExpressAdapter(), {
    logger: false,
    abortOnError: false,
  });
  t.after(() => app.close());
  configureApp(app);
  await app.init();
  const api = request(app.getHttpServer());
  const credentials = {
    username: 'owner',
    password: 'test-password-long',
  };
  const a = await api.post('/api/v1/auth/setup').send(credentials).expect(201);
  const auth = `Bearer ${a.body.accessToken}`,
    other = 'Bearer ' + '0'.repeat(64);
  const c = await api
      .post('/api/v1/conversations')
      .set('Authorization', auth)
      .send({ title: '文案' })
      .expect(201),
    id = c.body.id;
  const sent = await api
    .post(`/api/v1/conversations/${id}/messages`)
    .set('Authorization', auth)
    .send({ content: '手机发送的文案' })
    .expect(201);
  assert.equal(sent.body.conversationId, id);
  const device = await api
    .post('/api/v1/auth/login')
    .send({ username: credentials.username, password: credentials.password })
    .expect(200);
  const history = await api
    .get(`/api/v1/conversations/${id}/messages`)
    .set('Authorization', `Bearer ${device.body.accessToken}`)
    .query({ q: '手机' })
    .expect(200);
  assert.equal(history.body.items[0].content, '手机发送的文案');
  const found = await api
    .get('/api/v1/conversations')
    .set('Authorization', auth)
    .query({ q: '手机' })
    .expect(200);
  assert.equal(found.body.items[0].id, id);
  await api.get(`/api/v1/conversations/${id}/messages`).set('Authorization', other).expect(401);
  await api
    .post(`/api/v1/conversations/${id}/messages`)
    .set('Authorization', other)
    .send({ content: 'x' })
    .expect(401);
  await api
    .patch(`/api/v1/conversations/${id}`)
    .set('Authorization', auth)
    .send({ title: '新名称' })
    .expect(200);
  await api.delete(`/api/v1/conversations/${id}`).set('Authorization', other).expect(401);
  await api.delete(`/api/v1/conversations/${id}`).set('Authorization', auth).expect(204);
  await api.get(`/api/v1/messages/${sent.body.id}`).set('Authorization', auth).expect(404);
});
