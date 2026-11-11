const { test } = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const { NestFactory } = require('@nestjs/core');
const { ExpressAdapter } = require('@nestjs/platform-express');
const request = require('supertest');
process.env.DATABASE_PATH = ':memory:';
process.env.NODE_ENV = 'test';
const { AppModule } = require('../dist/app.module');
const { configureApp } = require('../dist/app.setup');
test('installation binding is stable, private, collision safe and compatible with existing devices', async (t) => {
  const app = await NestFactory.create(AppModule, new ExpressAdapter(), {
    logger: false,
    abortOnError: false,
  });
  t.after(() => app.close());
  configureApp(app);
  await app.init();
  const api = request(app.getHttpServer());
  const credentials = { username: 'device-owner', password: 'long-test-password' };
  const setup = await api.post('/api/v1/auth/setup').send(credentials).expect(201);
  const auth = 'Bearer ' + setup.body.accessToken;
  const login = await api.post('/api/v1/auth/login').send(credentials).expect(200);
  const auth2 = 'Bearer ' + login.body.accessToken;
  const base = { name: '浏览器', platform: 'web' };
  const register = (body, token = auth) =>
    api.post('/api/v1/devices').set('Authorization', token).send(body);
  const old = await register({ ...base, name: '已命名的旧设备' }).expect(201);
  assert.equal(old.body.fingerprintBound, false);
  const identity = { installationId: randomUUID(), fingerprint: '{"platform":"Mac","version":1}' };
  await api
    .post('/api/v1/devices')
    .send({ ...base, ...identity })
    .expect(401);
  for (const extra of [
    { installationId: 'bad' },
    { installationId: null },
    { fingerprint: identity.fingerprint },
    { ...identity, fingerprint: null },
    { ...identity, fingerprint: 'x'.repeat(1025) },
  ]) {
    await register({ ...base, ...extra }).expect(400);
  }
  const bound = await register({ ...base, ...identity, id: old.body.id }).expect(201);
  assert.equal(bound.body.id, old.body.id);
  assert.equal(bound.body.name, '已命名的旧设备');
  assert.equal(bound.body.fingerprintBound, true);
  assert.equal(bound.body.installation_hash, undefined);
  assert.equal(bound.body.fingerprint_hash, undefined);
  const pair = await Promise.all([
    register({ ...base, ...identity }, auth),
    register({ ...base, ...identity }, auth2),
  ]);
  pair.forEach((result) => {
    assert.equal(result.status, 201);
    assert.equal(result.body.id, old.body.id);
  });
  const me = await api.get('/api/v1/auth/me').set('Authorization', auth2).expect(200);
  assert.equal(me.body.deviceId, old.body.id);
  const changed = await register({
    ...base,
    ...identity,
    fingerprint: 'updated environment',
  }).expect(201);
  assert.equal(changed.body.id, old.body.id);
  await register({ ...base, ...identity, installationId: randomUUID(), id: old.body.id }).expect(
    409,
  );
  const other = await register({ ...base, ...identity, installationId: randomUUID() }).expect(201);
  assert.notEqual(
    other.body.id,
    old.body.id,
    'same fingerprint must not merge distinct installations',
  );
  const list = await api.get('/api/v1/devices').set('Authorization', auth).expect(200);
  assert.equal(list.body.length, 2);
  const rename = await api
    .patch(`/api/v1/devices/${old.body.id}`)
    .set('Authorization', auth)
    .send({ name: '新名称' })
    .expect(200);
  assert.equal(rename.body.fingerprintBound, true);
  const reuse = await register({ ...base, ...identity }, auth2).expect(201);
  assert.equal(reuse.body.name, '新名称');
  const legacy = await register({ name: '旧客户端', platform: 'android' }).expect(201);
  await register({ name: '旧客户端改名', platform: 'android', id: legacy.body.id }).expect(201);
});

test('browser fingerprint reuses a device across private sessions without storage and upgrades legacy records', async (t) => {
  const app = await NestFactory.create(AppModule, new ExpressAdapter(), {
    logger: false,
    abortOnError: false,
  });
  t.after(() => app.close());
  configureApp(app);
  await app.init();
  const api = request(app.getHttpServer());
  const credentials = { username: 'fingerprint-owner', password: 'long-test-password' };
  const setup = await api.post('/api/v1/auth/setup').send(credentials).expect(201);
  const login = await api.post('/api/v1/auth/login').send(credentials).expect(200);
  const auth = 'Bearer ' + setup.body.accessToken;
  const privateAuth = 'Bearer ' + login.body.accessToken;
  const base = { name: 'Web 浏览器', platform: 'web' };
  const register = (body, token = auth) =>
    api
      .post('/api/v1/devices')
      .set('Authorization', token)
      .send({ ...base, ...body });
  const old = await register({
    name: '办公电脑',
    installationId: randomUUID(),
    fingerprint: 'old-v1-hints',
  }).expect(201);
  const identity = { identityMode: 'fingerprint', fingerprint: '{"version":2,"gpu":"A"}' };
  await api
    .post('/api/v1/devices')
    .send({ ...base, ...identity })
    .expect(401);
  for (const extra of [
    { identityMode: 'fingerprint' },
    { ...identity, fingerprint: ' ' },
    { ...identity, fingerprint: null },
    { ...identity, platform: 'android' },
    { ...identity, identityMode: 'unsupported' },
  ])
    await register(extra).expect(400);
  const upgraded = await register({ ...identity, id: old.body.id }).expect(201);
  assert.equal(upgraded.body.id, old.body.id);
  assert.equal(upgraded.body.name, '办公电脑');
  assert.equal(upgraded.body.identityMode, 'fingerprint');
  assert.equal(upgraded.body.fingerprintBound, true);
  for (const key of [
    'browser_fingerprint_hash',
    'installation_hash',
    'fingerprint_hash',
    'fingerprint',
  ])
    assert.equal(upgraded.body[key], undefined);
  const sessions = await Promise.all([
    register(identity, privateAuth),
    register({ ...identity, installationId: randomUUID() }),
  ]);
  for (const result of sessions) {
    assert.equal(result.status, 201);
    assert.equal(result.body.id, old.body.id);
    assert.equal(result.body.name, '办公电脑');
  }
  const me = await api.get('/api/v1/auth/me').set('Authorization', privateAuth).expect(200);
  assert.equal(me.body.deviceId, old.body.id);
  await register({ id: old.body.id }).expect(409);
  await register({ ...identity, id: old.body.id, fingerprint: 'different-browser' }).expect(409);
  const other = await register({ ...identity, fingerprint: 'different-browser' }).expect(201);
  assert.notEqual(other.body.id, old.body.id);
  // A stale cached ID must never override the canonical fingerprint match.
  const canonical = await register({ ...identity, id: other.body.id }).expect(201);
  assert.equal(canonical.body.id, old.body.id);
  const fresh = await Promise.all([
    register({ ...identity, fingerprint: 'new-concurrent' }),
    register({ ...identity, fingerprint: 'new-concurrent' }),
  ]);
  assert.equal(fresh[0].status, 201);
  assert.equal(fresh[1].status, 201);
  assert.equal(fresh[0].body.id, fresh[1].body.id);
  const list = await api.get('/api/v1/devices').set('Authorization', auth).expect(200);
  assert.equal(list.body.length, 3);
  // All sessions grouped under this device are revoked when the device is removed.
  await register(identity, auth);
  await api.delete(`/api/v1/devices/${old.body.id}`).set('Authorization', auth).expect(204);
  await api.get('/api/v1/auth/me').set('Authorization', privateAuth).expect(401);
  await api.get('/api/v1/auth/me').set('Authorization', auth).expect(401);
});

test('native platforms reuse installation identity and retain custom names across login sessions', async (t) => {
  const app = await NestFactory.create(AppModule, new ExpressAdapter(), {
    logger: false,
    abortOnError: false,
  });
  t.after(() => app.close());
  configureApp(app);
  await app.init();
  const api = request(app.getHttpServer());
  const credentials = { username: 'native-owner', password: 'long-test-password' };
  const setup = await api.post('/api/v1/auth/setup').send(credentials).expect(201);
  const auth = 'Bearer ' + setup.body.accessToken;
  const register = (body, token = auth) =>
    api.post('/api/v1/devices').set('Authorization', token).send(body);
  const installationId = randomUUID();
  const ids = new Set();
  for (const platform of ['ios', 'ipados', 'macos', 'android', 'windows']) {
    const old = await register({ name: '同名设备', platform }).expect(201);
    const upgraded = await register({
      name: '客户端旧名称',
      platform,
      id: old.body.id,
      installationId,
    }).expect(201);
    assert.equal(upgraded.body.id, old.body.id);
    assert.equal(upgraded.body.identityMode, 'installation');
    await api
      .patch(`/api/v1/devices/${old.body.id}`)
      .set('Authorization', auth)
      .send({ name: '用户自定义名称' })
      .expect(200);
    const login = await api.post('/api/v1/auth/login').send(credentials).expect(200);
    const nextAuth = 'Bearer ' + login.body.accessToken;
    const again = await register(
      { name: '客户端旧名称', platform, installationId },
      nextAuth,
    ).expect(201);
    assert.equal(again.body.id, old.body.id);
    assert.equal(again.body.name, '用户自定义名称');
    const me = await api.get('/api/v1/auth/me').set('Authorization', nextAuth).expect(200);
    assert.equal(me.body.deviceId, old.body.id);
    const different = await register({
      name: '同名设备',
      platform,
      installationId: randomUUID(),
    }).expect(201);
    assert.notEqual(different.body.id, old.body.id);
    ids.add(again.body.id);
  }
  assert.equal(ids.size, 5, 'the platform scopes installation identity');
});
