const { test } = require('node:test');
const assert = require('node:assert/strict');
const { NestFactory } = require('@nestjs/core');
const { ExpressAdapter } = require('@nestjs/platform-express');
const request = require('supertest');
process.env.DATABASE_PATH = ':memory:';
process.env.NODE_ENV = 'test';
const { AppModule } = require('../dist/app.module');
const { configureApp } = require('../dist/app.setup');
test('annotations persist, share across sessions, validate and participate in every search', async (t) => {
  const app = await NestFactory.create(AppModule, new ExpressAdapter(), {
    logger: false,
    abortOnError: false,
  });
  t.after(() => app.close());
  configureApp(app);
  await app.init();
  const api = request(app.getHttpServer());
  const credentials = { username: 'notes-owner', password: 'test-password-long' };
  const setup = await api.post('/api/v1/auth/setup').send(credentials).expect(201);
  const auth = `Bearer ${setup.body.accessToken}`;
  const c = await api
    .post('/api/v1/conversations')
    .set('Authorization', auth)
    .send({ title: '普通会话' })
    .expect(201);
  const m = await api
    .post(`/api/v1/conversations/${c.body.id}/messages`)
    .set('Authorization', auth)
    .send({ content: '原始文字' })
    .expect(201);
  assert.equal(m.body.annotation, '');
  const path = `/api/v1/messages/${m.body.id}`;
  await api.patch(path).send({ annotation: '拒绝匿名' }).expect(401);
  for (const invalid of [null, 12, 'x'.repeat(2001)]) {
    await api.patch(path).set('Authorization', auth).send({ annotation: invalid }).expect(400);
  }
  const note = '会议材料 100%_完成\\归档\n第二行';
  const updated = await api
    .patch(path)
    .set('Authorization', auth)
    .send({ annotation: `  ${note}  `, isStarred: true })
    .expect(200);
  assert.equal(updated.body.annotation, note);
  assert.equal(updated.body.content, '原始文字');
  const login = await api.post('/api/v1/auth/login').send(credentials).expect(200);
  const other = `Bearer ${login.body.accessToken}`;
  const detail = await api.get(path).set('Authorization', other).expect(200);
  assert.equal(detail.body.annotation, note);
  const endpoints = [
    '/api/v1/messages',
    '/api/v1/messages/starred',
    `/api/v1/conversations/${c.body.id}/messages`,
    '/api/v1/conversations',
  ];
  for (const endpoint of endpoints) {
    const result = await api
      .get(endpoint)
      .set('Authorization', other)
      .query({ q: '100%_完成\\归档' })
      .expect(200);
    assert.equal(result.body.total, 1, endpoint);
  }
  await api.patch(path).set('Authorization', other).send({ annotation: '已修改批注' }).expect(200);
  const old = await api
    .get('/api/v1/messages')
    .set('Authorization', auth)
    .query({ q: '会议材料' })
    .expect(200);
  assert.equal(old.body.total, 0);
  await api.patch(path).set('Authorization', auth).send({ annotation: '   ' }).expect(200);
  for (const endpoint of endpoints) {
    const result = await api
      .get(endpoint)
      .set('Authorization', auth)
      .query({ q: '已修改批注' })
      .expect(200);
    assert.equal(result.body.total, 0, endpoint);
  }
  const cleared = await api.get(path).set('Authorization', auth).expect(200);
  assert.equal(cleared.body.annotation, '');
  assert.equal(cleared.body.content, '原始文字');
});
