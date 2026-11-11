const { test } = require('node:test');
const assert = require('node:assert/strict');
const { NestFactory } = require('@nestjs/core');
const { ExpressAdapter } = require('@nestjs/platform-express');
const { DataSource } = require('typeorm');
const request = require('supertest');
const { mkdtempSync, rmSync } = require('node:fs');
const { tmpdir } = require('node:os');
const { join } = require('node:path');
const { randomUUID } = require('node:crypto');
const directory = mkdtempSync(join(tmpdir(), 'syncbox-single-'));
process.env.DATABASE_PATH = join(directory, 'test.sqlite');
process.env.NODE_ENV = 'test';
const { AppModule } = require('../dist/app.module');
const { configureApp } = require('../dist/app.setup');
test('single owner setup, concurrent initialization, login and persistent shared messages', async (t) => {
  const app = await NestFactory.create(AppModule, new ExpressAdapter(), {
    logger: false,
    abortOnError: false,
  });
  configureApp(app);
  await app.init();
  t.after(async () => {
    await app.close();
    rmSync(directory, { recursive: true, force: true });
  });
  const api = request(app.getHttpServer()),
    db = app.get(DataSource);
  assert.deepEqual((await api.get('/api/v1/auth/status').expect(200)).body, { initialized: false });
  await api.post('/api/v1/auth/setup').send({ username: 'owner', password: 'short' }).expect(400);
  const input = { username: ' Owner ', password: 'six123' };
  const results = await Promise.all([
    api.post('/api/v1/auth/setup').send(input),
    api.post('/api/v1/auth/setup').send(input),
  ]);
  assert.deepEqual(results.map((x) => x.status).sort(), [201, 409]);
  const session = results.find((x) => x.status === 201).body;
  assert.equal(session.user.username, 'owner');
  const auth = `Bearer ${session.accessToken}`;
  assert.deepEqual((await api.get('/api/v1/auth/status').expect(200)).body, { initialized: true });
  await api
    .post('/api/v1/auth/setup')
    .send({ username: 'second', password: input.password })
    .expect(409);
  await api.post('/api/v1/auth/register').send(input).expect(404);
  const [user] = await db.query('SELECT * FROM users');
  assert.notEqual(user.password_hash, input.password);
  await assert.rejects(
    db.query(
      'INSERT INTO users (id,email,name,password_hash,created_at,username) VALUES (?,?,?,?,?,?)',
      ['other', 'other', 'other', 'hash', 'now', 'other'],
    ),
    /UNIQUE/,
  );
  await api
    .post('/api/v1/auth/login')
    .send({ username: 'owner', password: 'wrong-password' })
    .expect(401);
  await api.post('/api/v1/auth/login').send({ username: 'owner', password: 'short' }).expect(400);
  const phone = await api
    .post('/api/v1/auth/login')
    .send({ username: 'OWNER', password: input.password })
    .expect(200);
  const phoneAuth = `Bearer ${phone.body.accessToken}`;
  const device = await api
    .post('/api/v1/devices')
    .set('Authorization', phoneAuth)
    .send({ name: 'iPhone', platform: 'ios' })
    .expect(201);
  const sent = await api
    .post('/api/v1/messages')
    .set('Authorization', phoneAuth)
    .send({ title: '100%_中文', content: '跨端内容 SQLite' })
    .expect(201);
  assert.equal(sent.body.senderDevice.id, device.body.id);
  const clientId = randomUUID();
  const firstRetry = await api
    .post('/api/v1/messages')
    .set('Authorization', phoneAuth)
    .send({ title: '离线重试', content: '只应保存一次', clientId })
    .expect(201);
  const secondRetry = await api
    .post('/api/v1/messages')
    .set('Authorization', phoneAuth)
    .send({ title: '离线重试', content: '只应保存一次', clientId })
    .expect(201);
  assert.equal(secondRetry.body.id, firstRetry.body.id);
  await api.get('/api/v1/events').expect(401);
  await api.get(`/api/v1/messages/${sent.body.id}`).set('Authorization', auth).expect(200);
  for (const q of ['中文', 'SQLite', '%', '_']) {
    const response = await api
      .get('/api/v1/messages')
      .query({ q })
      .set('Authorization', auth)
      .expect(200);
    assert.equal(response.body.total, 1);
  }
  const injection = await api
    .get('/api/v1/messages')
    .query({ q: "' OR 1=1 --" })
    .set('Authorization', auth)
    .expect(200);
  assert.equal(injection.body.total, 0);
  await api.get('/api/v1/messages?pageSize=101').set('Authorization', auth).expect(400);
  await api
    .patch(`/api/v1/messages/${sent.body.id}`)
    .set('Authorization', auth)
    .send({ isStarred: true })
    .expect(200);
  await api.get('/api/v1/messages').expect(401);
  await api.delete(`/api/v1/devices/${device.body.id}`).set('Authorization', auth).expect(204);
  await api.get('/api/v1/auth/me').set('Authorization', phoneAuth).expect(401);
  await api.get(`/api/v1/messages/${sent.body.id}`).set('Authorization', auth).expect(200);
  await api.post('/api/v1/auth/logout').set('Authorization', auth).expect(204);
  await api.get('/api/v1/auth/me').set('Authorization', auth).expect(401);
  await db.destroy();
  await db.initialize();
  assert.equal((await api.get('/api/v1/auth/status')).body.initialized, true);
  await api.post('/api/v1/auth/setup').send(input).expect(409);
  await api
    .post('/api/v1/auth/login')
    .send({ username: 'owner', password: input.password })
    .expect(200);
});
