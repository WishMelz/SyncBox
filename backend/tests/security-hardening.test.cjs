const { test } = require('node:test');
const assert = require('node:assert/strict');
const { execFileSync } = require('node:child_process');
const { join } = require('node:path');
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
const { totp } = require('../dist/modules/auth/totp');

async function createApp(t, envOverrides = {}) {
  const previous = {};
  for (const [k, v] of Object.entries(envOverrides)) {
    previous[k] = process.env[k];
    process.env[k] = v;
  }
  const app = await NestFactory.create(AppModule, new ExpressAdapter(), { logger: false });
  configureApp(app);
  await app.init();
  t.after(async () => {
    app.getHttpServer()?.closeAllConnections?.();
    await app.close();
    for (const [k, v] of Object.entries(previous)) {
      if (v === undefined) delete process.env[k];
      else process.env[k] = v;
    }
  });
  return app;
}

async function readEventUntil(reader, predicate, timeoutMs = 4000) {
  const decoder = new TextDecoder();
  let text = '';
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const remaining = Math.max(20, deadline - Date.now());
    const result = await Promise.race([
      reader.read(),
      new Promise((_, reject) =>
        setTimeout(() => reject(new Error('SSE read timeout')), remaining),
      ),
    ]);
    if (result.done) return { done: true, text };
    text += decoder.decode(result.value, { stream: true });
    if (predicate(text)) return { done: false, text };
  }
  throw new Error('SSE predicate timed out. Received: ' + text);
}

test('TRUST_PROXY=false ignores X-Forwarded-For spoofing while TRUST_PROXY=true honors 1 proxy hop', async (t) => {
  const appDirect = await createApp(t, { TRUST_PROXY: 'false' });
  const apiDirect = request(appDirect.getHttpServer());
  await apiDirect
    .post('/api/v1/auth/setup')
    .send({ username: 'p01', password: 'Password-2026' })
    .expect(201);
  for (let i = 0; i < 10; i++) {
    await apiDirect
      .post('/api/v1/auth/login')
      .set('X-Forwarded-For', `198.51.100.${i + 1}`)
      .send({ username: 'p01', password: 'wrong-password' })
      .expect(401);
  }
  // Spoofing a new IP must NOT bypass rate limiting when TRUST_PROXY=false.
  await apiDirect
    .post('/api/v1/auth/login')
    .set('X-Forwarded-For', '198.51.100.250')
    .send({ username: 'p01', password: 'wrong-password' })
    .expect(429);

  // Boot a clean process with TRUST_PROXY=true so ConfigModule evaluates TRUST_PROXY=true at load time.
  const proxyScript = `
    const assert = require('node:assert/strict');
    const { NestFactory } = require('@nestjs/core');
    const { ExpressAdapter } = require('@nestjs/platform-express');
    const request = require('supertest');
    const { AppModule } = require('./dist/app.module');
    const { configureApp } = require('./dist/app.setup');
    (async () => {
      const app = await NestFactory.create(AppModule, new ExpressAdapter(), { logger: false });
      configureApp(app);
      await app.init();
      const api = request(app.getHttpServer());
      await api.post('/api/v1/auth/setup').send({ username: 'p01p', password: 'Password-2026' }).expect(201);
      for (let i = 0; i < 10; i++) {
        await api
          .post('/api/v1/auth/login')
          .set('X-Forwarded-For', '203.0.113.10')
          .send({ username: 'p01p', password: 'wrong-password' })
          .expect(401);
      }
      await api
        .post('/api/v1/auth/login')
        .set('X-Forwarded-For', '203.0.113.10')
        .send({ username: 'p01p', password: 'wrong-password' })
        .expect(429);
      await api
        .post('/api/v1/auth/login')
        .set('X-Forwarded-For', '203.0.113.11')
        .send({ username: 'p01p', password: 'wrong-password' })
        .expect(401);
      await app.close();
    })();
  `;
  execFileSync(process.execPath, ['-e', proxyScript], {
    cwd: join(__dirname, '..'),
    env: { ...process.env, DATABASE_PATH: ':memory:', NODE_ENV: 'test', TRUST_PROXY: 'true' },
    stdio: 'inherit',
  });
});

test('sensitive settings endpoints rate-limit password/TOTP brute force across failures', async (t) => {
  const app = await createApp(t, { TRUST_PROXY: 'false' });
  const api = request(app.getHttpServer());
  const creds = { username: 'sec-owner', password: 'Secret-Password-2026' };
  const owner = (await api.post('/api/v1/auth/setup').send(creds).expect(201)).body;
  const auth = { Authorization: `Bearer ${owner.accessToken}` };

  for (let i = 0; i < 5; i++) {
    await api
      .post('/api/v1/settings/two-factor/setup')
      .set(auth)
      .send({ password: 'wrong-password' })
      .expect(401);
  }
  await api
    .post('/api/v1/settings/two-factor/setup')
    .set(auth)
    .send({ password: creds.password })
    .expect(429);
  await api
    .delete('/api/v1/settings/data')
    .set(auth)
    .send({ password: creds.password, confirmation: '删除所有数据' })
    .expect(429);
});

test('SSE streams bind to sessions/devices, close immediately on revocation, and close on expired heartbeat', async (t) => {
  const app = await createApp(t, { SSE_HEARTBEAT_MS: '35' });
  await app.listen(0, '127.0.0.1');
  const controllerA = new AbortController();
  const controllerB = new AbortController();
  t.after(async () => {
    controllerA.abort();
    controllerB.abort();
    app.getHttpServer().closeAllConnections();
  });
  const baseUrl = await app.getUrl();
  const api = request(app.getHttpServer());
  const db = app.get(DataSource);

  const creds = { username: 'sse-owner', password: 'SSE-Password-2026' };
  const sA = (await api.post('/api/v1/auth/setup').send(creds).expect(201)).body;
  const sB = (await api.post('/api/v1/auth/login').send(creds).expect(200)).body;
  const authA = { Authorization: `Bearer ${sA.accessToken}` };
  const authB = { Authorization: `Bearer ${sB.accessToken}` };

  const devA = (
    await api
      .post('/api/v1/devices')
      .set(authA)
      .send({ name: 'Mac', platform: 'macos' })
      .expect(201)
  ).body;
  const devB = (
    await api
      .post('/api/v1/devices')
      .set(authB)
      .send({ name: 'Phone', platform: 'ios' })
      .expect(201)
  ).body;

  const streamA = await fetch(`${baseUrl}/api/v1/events`, {
    headers: authA,
    signal: controllerA.signal,
  });
  const streamB = await fetch(`${baseUrl}/api/v1/events`, {
    headers: authB,
    signal: controllerB.signal,
  });
  const readerA = streamA.body.getReader();
  const readerB = streamB.body.getReader();

  // Revoke device B -> B's SSE closes immediately, A stays open.
  await api.delete(`/api/v1/devices/${devB.id}`).set(authA).expect(204);
  const resB = await readEventUntil(readerB, () => false);
  assert.equal(resB.done, true);

  // Verify A still receives events!
  const conv = (
    await api.post('/api/v1/conversations').set(authA).send({ title: 'AfterRevoke' }).expect(201)
  ).body;
  const resA = await readEventUntil(readerA, (txt) => txt.includes(conv.id));
  assert.equal(resA.done, false);

  // Enable 2FA on A -> any other session C gets closed immediately, while A stays open.
  const sC = (await api.post('/api/v1/auth/login').send(creds).expect(200)).body;
  const authC = { Authorization: `Bearer ${sC.accessToken}` };
  const streamC = await fetch(`${baseUrl}/api/v1/events`, {
    headers: authC,
    signal: controllerB.signal,
  });
  const readerC = streamC.body.getReader();
  const setup2fa = (
    await api
      .post('/api/v1/settings/two-factor/setup')
      .set(authA)
      .send({ password: creds.password })
      .expect(201)
  ).body;
  await api
    .post('/api/v1/settings/two-factor/enable')
    .set(authA)
    .send({ password: creds.password, code: totp(setup2fa.secret, Math.floor(Date.now() / 30000)) })
    .expect(201);
  const resC = await readEventUntil(readerC, () => false);
  assert.equal(resC.done, true);

  // Heartbeat 3-tick session re-validation: directly expire session A in DB -> stream A closes within ~200ms.
  await db.query('DELETE FROM sessions WHERE user_id = ?', [sA.user.id]);
  const resAEnd = await readEventUntil(readerA, () => false);
  assert.equal(resAEnd.done, true);
  assert.ok(devA.id);
});

test('SSE events cover message edit/delete, markRead, conversation delete, cleanup, and file category filter', async (t) => {
  const app = await createApp(t);
  await app.listen(0, '127.0.0.1');
  const controller = new AbortController();
  t.after(async () => {
    controller.abort();
    app.getHttpServer().closeAllConnections();
  });
  const api = request(app.getHttpServer());
  const db = app.get(DataSource);
  const settingsService = app.get(SettingsService);

  const creds = { username: 'events-full', password: 'Events-Password-2026' };
  const session = (await api.post('/api/v1/auth/setup').send(creds).expect(201)).body;
  const auth = { Authorization: `Bearer ${session.accessToken}` };
  await api.post('/api/v1/devices').set(auth).send({ name: 'Web', platform: 'web' }).expect(201);

  const stream = await fetch(`${await app.getUrl()}/api/v1/events`, {
    headers: auth,
    signal: controller.signal,
  });
  const reader = stream.body.getReader();

  const c = (await api.post('/api/v1/conversations').set(auth).send({ title: 'C1' }).expect(201))
    .body;
  const msg = (
    await api
      .post(`/api/v1/conversations/${c.id}/messages`)
      .set(auth)
      .send({ content: 'hello' })
      .expect(201)
  ).body;

  // Edit content -> should emit conversations + messages.
  await api.patch(`/api/v1/messages/${msg.id}`).set(auth).send({ content: 'edited' }).expect(200);
  const editChunk = await readEventUntil(
    reader,
    (txt) => txt.includes('"scope":"conversations"') && txt.includes(c.id),
  );
  assert.match(editChunk.text, /"scope":"messages"/);

  // markRead -> emits conversations + messages.
  await api.patch(`/api/v1/conversations/${c.id}/read`).set(auth).expect(204);
  await readEventUntil(reader, (txt) => txt.includes('"scope":"conversations"'));

  // File center category filter: upload attachment image + txt + legacy image.
  const png = await sharp({ create: { width: 16, height: 16, channels: 3, background: '#118833' } })
    .png()
    .toBuffer();
  const attMsg = (
    await api
      .post(`/api/v1/conversations/${c.id}/attachments`)
      .set(auth)
      .field('names', JSON.stringify(['photo.png', 'note.txt']))
      .attach('files', png, 'photo.png')
      .attach('files', Buffer.from('note'), 'note.txt')
      .expect(201)
  ).body;
  const legacyImg = (
    await api
      .post(`/api/v1/conversations/${c.id}/images`)
      .set(auth)
      .attach('image', png, 'legacy.png')
      .expect(201)
  ).body;

  const imagesOnly = (await api.get('/api/v1/messages/files?category=image').set(auth).expect(200))
    .body;
  assert.equal(imagesOnly.total, 2);
  assert.deepEqual(imagesOnly.items.map((x) => x.kind).sort(), ['attachment', 'image']);
  assert.ok(imagesOnly.items.every((x) => x.category === 'image'));

  const filesOnly = (await api.get('/api/v1/messages/files?category=file').set(auth).expect(200))
    .body;
  assert.equal(filesOnly.total, 1);
  assert.equal(filesOnly.items[0].name, 'note.txt');
  assert.equal(filesOnly.items[0].category, 'file');

  // DB write throttling (P1-5): set device last_seen_at to 2020 and attachment last_accessed_at to 60s ago.
  const now = Date.now();
  await db.query('UPDATE devices SET last_seen_at = ?', ['2020-01-01T00:00:00.000Z']);
  await db.query('UPDATE message_attachments SET last_accessed_at = ? WHERE id = ?', [
    now - 60_000,
    attMsg.attachments[0].id,
  ]);
  for (let i = 0; i < 5; i++) {
    await api
      .get(`/api/v1/messages/${attMsg.id}/attachments/${attMsg.attachments[0].id}/preview`)
      .set(auth)
      .expect(200);
  }
  const [devRow] = await db.query('SELECT last_seen_at FROM devices');
  assert.equal(devRow.last_seen_at, '2020-01-01T00:00:00.000Z');
  const [attRow] = await db.query('SELECT last_accessed_at FROM message_attachments WHERE id = ?', [
    attMsg.attachments[0].id,
  ]);
  assert.equal(attRow.last_accessed_at, now - 60_000);

  // includeTotal=false (P1-6)
  const noTotal = (
    await api
      .get(`/api/v1/conversations/${c.id}/messages?includeTotal=false&pageSize=1`)
      .set(auth)
      .expect(200)
  ).body;
  assert.equal(noTotal.total, undefined);
  assert.equal(noTotal.totalPages, undefined);
  assert.equal(noTotal.hasMore, true);
  assert.ok(noTotal.nextCursor);

  // Cleanup emits settings/favorites/messages/conversations (P0-4)
  await api
    .patch('/api/v1/settings/cleanup')
    .set(auth)
    .send({ enabled: true, idleDays: 30 })
    .expect(200);
  await db.query('UPDATE message_images SET last_accessed_at = ?', [now - 31 * 86400000]);
  assert.equal(await settingsService.cleanup(now), 1);
  const cleanupEvents = await readEventUntil(
    reader,
    (txt) => txt.includes('"scope":"settings"') && txt.includes(c.id),
  );
  assert.match(cleanupEvents.text, /"scope":"favorites"/);

  // Delete message emits conversations (P0-4)
  await api.delete(`/api/v1/messages/${legacyImg.id}`).set(auth).expect(204);
  const delEvents = await readEventUntil(
    reader,
    (txt) => txt.includes(legacyImg.id) && txt.includes('"scope":"conversations"'),
  );
  assert.match(delEvents.text, /"scope":"messages"/);

  await reader.cancel();
});
