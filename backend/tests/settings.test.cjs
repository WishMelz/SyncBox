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
const { SettingsService } = require('../dist/modules/settings/settings.service');
const {
  totp,
  matchCounter,
  newSecret,
  sealSecret,
  openSecret,
} = require('../dist/modules/auth/totp');
async function fixture(t) {
  const app = await NestFactory.create(AppModule, new ExpressAdapter(), { logger: false });
  t.after(() => app.close());
  configureApp(app);
  await app.init();
  const api = request(app.getHttpServer());
  const login = { username: 'settings-test', password: 'Settings-test-2026' };
  const owner = (await api.post('/api/v1/auth/setup').send(login).expect(201)).body;
  const auth = { Authorization: `Bearer ${owner.accessToken}` };
  return {
    app,
    api,
    login,
    owner,
    auth,
    db: app.get(DataSource),
    service: app.get(SettingsService),
  };
}
test('TOTP matches RFC 6238 SHA1 vectors and encrypts secrets with the owner password', async () => {
  const secret = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';
  for (const [time, expected] of [
    [59, '287082'],
    [1111111109, '081804'],
    [1111111111, '050471'],
    [1234567890, '005924'],
    [2000000000, '279037'],
    [20000000000, '353130'],
  ]) {
    assert.equal(totp(secret, Math.floor(time / 30)), expected);
    assert.equal(matchCounter(secret, expected, -1, time * 1000), Math.floor(time / 30));
    assert.equal(matchCounter(secret, expected, Math.floor(time / 30), time * 1000), null);
  }
  assert.match(newSecret(), /^[A-Z2-7]{32}$/);
  const encrypted = await sealSecret(secret, 'test-password');
  assert.ok(!encrypted.includes(secret));
  assert.equal(await openSecret(encrypted, 'test-password'), secret);
  await assert.rejects(openSecret(encrypted, 'wrong-password'));
});
test('cleanup preserves messages, tracks real reads, handles old images, and is disabled by default', async (t) => {
  const { api, auth, db, service, owner } = await fixture(t);
  await api.get('/api/v1/settings').expect(401);
  const settings = (await api.get('/api/v1/settings').set(auth).expect(200)).body;
  assert.equal(settings.cleanup.enabled, false);
  assert.equal(settings.cleanup.idleDays, 30);
  assert.equal(settings.twoFactorEnabled, false);
  assert.equal(JSON.stringify(settings).includes('secret'), false);
  const c = (
    await api.post('/api/v1/conversations').set(auth).send({ title: 'cleanup' }).expect(201)
  ).body;
  const png = await sharp({ create: { width: 16, height: 16, channels: 3, background: '#123456' } })
    .png()
    .toBuffer();
  const sent = (
    await api
      .post(`/api/v1/conversations/${c.id}/attachments`)
      .set(auth)
      .field('content', '保留说明')
      .attach('files', png, 'picture.png')
      .attach('files', Buffer.from('content'), 'file.txt')
      .expect(201)
  ).body;
  const oldImage = (
    await api
      .post(`/api/v1/conversations/${c.id}/images`)
      .set(auth)
      .attach('image', png, 'old.png')
      .expect(201)
  ).body;
  const now = Date.now(),
    stale = now - 31 * 86400000;
  await db.query('UPDATE message_attachments SET last_accessed_at=?', [stale]);
  await db.query('UPDATE message_images SET last_accessed_at=?', [stale]);
  assert.equal(await service.cleanup(now), 0);
  const attachmentPath = `/api/v1/messages/${sent.id}/attachments/`;
  await api.get(attachmentPath + sent.attachments[0].id + '/preview').expect(401);
  assert.equal(
    (
      await db.query('SELECT last_accessed_at time FROM message_attachments WHERE id=?', [
        sent.attachments[0].id,
      ])
    )[0].time,
    stale,
  );
  await api
    .get(attachmentPath + sent.attachments[0].id + '/preview')
    .set(auth)
    .expect(200);
  await api.get(`/api/v1/conversations/${c.id}/messages`).set(auth).expect(200);
  assert.equal(
    (
      await db.query('SELECT last_accessed_at time FROM message_attachments WHERE id=?', [
        sent.attachments[1].id,
      ])
    )[0].time,
    stale,
  );
  for (const idleDays of [0, 3651, 1.5, '30', null])
    await api
      .patch('/api/v1/settings/cleanup')
      .set(auth)
      .send({ enabled: true, idleDays })
      .expect(400);
  await api
    .patch('/api/v1/settings/cleanup')
    .set(auth)
    .send({ enabled: 'true', idleDays: 30 })
    .expect(400);
  await api
    .patch('/api/v1/settings/cleanup')
    .set(auth)
    .send({ enabled: true, idleDays: 30 })
    .expect(200);
  assert.equal(await service.cleanup(now), 2);
  const detail = (await api.get(`/api/v1/messages/${sent.id}`).set(auth).expect(200)).body;
  assert.equal(detail.content, '保留说明');
  assert.equal(detail.attachments[1].deletedAt, now);
  assert.equal(detail.attachments[0].deletedAt, null);
  const cleared = (
    await db.query('SELECT length(data) bytes,preview FROM message_attachments WHERE id=?', [
      sent.attachments[1].id,
    ])
  )[0];
  assert.equal(cleared.bytes, 0);
  assert.equal(cleared.preview, null);
  await api
    .get(attachmentPath + sent.attachments[1].id)
    .set(auth)
    .expect(404);
  assert.equal(
    (await api.get(`/api/v1/messages/${oldImage.id}`).set(auth).expect(200)).body.filesExpired,
    true,
  );
  await api.get(`/api/v1/messages/${oldImage.id}/image`).set(auth).expect(404);
  await api
    .get(attachmentPath + sent.attachments[0].id)
    .set(auth)
    .expect(200);
  assert.equal((await api.get('/api/v1/settings').set(auth)).body.storage.fileCount, 1);
  // Boundary is inclusive and settings survive another login.
  await db.query('UPDATE message_attachments SET last_accessed_at=? WHERE id=?', [
    now - 30 * 86400000,
    sent.attachments[0].id,
  ]);
  assert.equal(await service.cleanup(now), 1);
  await api
    .patch('/api/v1/settings/cleanup')
    .set(auth)
    .send({ enabled: false, idleDays: 7 })
    .expect(200);
  assert.equal(
    (await db.query('SELECT idle_days FROM user_settings WHERE user_id=?', [owner.user.id]))[0]
      .idle_days,
    7,
  );
  assert.equal(await service.cleanup(now + 100 * 86400000), 0);
});
test('two-factor setup, replay rejection, one-use recovery, session revocation and disable', async (t) => {
  const { api, auth, owner, login, db } = await fixture(t);
  const second = (await api.post('/api/v1/auth/login').send(login).expect(200)).body;
  const secondAuth = { Authorization: `Bearer ${second.accessToken}` };
  await api
    .post('/api/v1/settings/two-factor/setup')
    .set(auth)
    .send({ password: 'wrong-pass' })
    .expect(401);
  const setup = (
    await api
      .post('/api/v1/settings/two-factor/setup')
      .set(auth)
      .send({ password: login.password })
      .expect(201)
  ).body;
  assert.match(setup.otpauthUri, /^otpauth:\/\/totp\/SyncBox/);
  assert.equal((await api.get('/api/v1/settings').set(auth)).body.twoFactorEnabled, false);
  const counter = Math.floor(Date.now() / 30000);
  const proof = { password: login.password, code: totp(setup.secret, counter) };
  await api.post('/api/v1/settings/two-factor/enable').set(secondAuth).send(proof).expect(400);
  const codes = (
    await api.post('/api/v1/settings/two-factor/enable').set(auth).send(proof).expect(201)
  ).body.recoveryCodes;
  assert.equal(codes.length, 8);
  assert.equal(new Set(codes).size, 8);
  const row = (await db.query('SELECT * FROM users WHERE id=?', [owner.user.id]))[0];
  assert.ok(!row.totp_secret.includes(setup.secret));
  assert.equal(row.totp_pending, null);
  assert.ok(!row.recovery_hashes.includes(codes[0]));
  await api.get('/api/v1/auth/me').set(secondAuth).expect(401);
  assert.equal(
    (await api.post('/api/v1/auth/login').send(login).expect(401)).body.code,
    'TWO_FACTOR_REQUIRED',
  );
  assert.notEqual(
    (
      await api
        .post('/api/v1/auth/login')
        .send({ ...login, password: 'wrong-password' })
        .expect(401)
    ).body.code,
    'TWO_FACTOR_REQUIRED',
  );
  await api
    .post('/api/v1/auth/login')
    .send({ ...login, code: proof.code })
    .expect(401);
  await api
    .post('/api/v1/auth/login')
    .send({ ...login, password: 'wrong-pass', code: codes[0] })
    .expect(401);
  const recovered = (
    await api
      .post('/api/v1/auth/login')
      .send({ ...login, code: codes[0] })
      .expect(200)
  ).body;
  await api
    .post('/api/v1/auth/login')
    .send({ ...login, code: codes[0] })
    .expect(401);
  assert.equal((await api.get('/api/v1/settings').set(auth)).body.recoveryCodesRemaining, 7);
  const next = { ...login, code: totp(setup.secret, counter + 1) };
  const concurrent = await Promise.all([
    api.post('/api/v1/auth/login').send(next),
    api.post('/api/v1/auth/login').send(next),
  ]);
  assert.deepEqual(concurrent.map((r) => r.status).sort(), [200, 401]);
  await api
    .post('/api/v1/settings/two-factor/disable')
    .set(auth)
    .send({ password: login.password })
    .expect(401);
  await api
    .post('/api/v1/settings/two-factor/disable')
    .set(auth)
    .send({ password: login.password, code: codes[1] })
    .expect(201);
  await api
    .get('/api/v1/auth/me')
    .set({ Authorization: `Bearer ${recovered.accessToken}` })
    .expect(401);
  assert.equal((await api.get('/api/v1/settings').set(auth)).body.twoFactorEnabled, false);
  await api.post('/api/v1/auth/login').send(login).expect(200);
});
test('reset requires exact confirmation, password and second factor, then clears all live data', async (t) => {
  const { api, auth, login, db } = await fixture(t);
  await api.post('/api/v1/devices').set(auth).send({ name: 'test', platform: 'web' }).expect(201);
  const c = (await api.post('/api/v1/conversations').set(auth).send({ title: 'private' })).body;
  await api
    .post(`/api/v1/conversations/${c.id}/attachments`)
    .set(auth)
    .attach('files', Buffer.from('private file'), 'secret.txt')
    .expect(201);
  await api
    .patch('/api/v1/settings/cleanup')
    .set(auth)
    .send({ enabled: false, idleDays: 30 })
    .expect(200);
  const setup = (
    await api.post('/api/v1/settings/two-factor/setup').set(auth).send({ password: login.password })
  ).body;
  const enabled = (
    await api
      .post('/api/v1/settings/two-factor/enable')
      .set(auth)
      .send({ password: login.password, code: totp(setup.secret, Math.floor(Date.now() / 30000)) })
      .expect(201)
  ).body;
  const body = {
    password: login.password,
    confirmation: '删除所有数据',
    code: enabled.recoveryCodes[0],
  };
  await api.delete('/api/v1/settings/data').send(body).expect(401);
  await api
    .delete('/api/v1/settings/data')
    .set(auth)
    .send({ ...body, confirmation: 'yes' })
    .expect(400);
  await api
    .delete('/api/v1/settings/data')
    .set(auth)
    .send({ ...body, password: 'wrong-pass' })
    .expect(401);
  await api
    .delete('/api/v1/settings/data')
    .set(auth)
    .send({ ...body, code: undefined })
    .expect(401);
  assert.equal((await db.query('SELECT COUNT(*) n FROM messages'))[0].n, 1);
  await api.delete('/api/v1/settings/data').set(auth).send(body).expect(204);
  for (const table of [
    'users',
    'sessions',
    'devices',
    'conversations',
    'messages',
    'message_images',
    'message_attachments',
    'user_settings',
  ])
    assert.equal((await db.query(`SELECT COUNT(*) n FROM ${table}`))[0].n, 0, table);
  assert.equal((await api.get('/api/v1/auth/status')).body.initialized, false);
  await api.get('/api/v1/auth/me').set(auth).expect(401);
  await api
    .post('/api/v1/auth/setup')
    .send({ username: 'new-owner', password: 'new-password' })
    .expect(201);
});
