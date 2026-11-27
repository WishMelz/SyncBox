const { test } = require('node:test');
const assert = require('node:assert/strict');
const { createHash } = require('node:crypto');
const { mkdtempSync, rmSync, writeFileSync, existsSync } = require('node:fs');
const { tmpdir } = require('node:os');
const { join } = require('node:path');
const { NestFactory } = require('@nestjs/core');
const { ExpressAdapter } = require('@nestjs/platform-express');
const { DataSource } = require('typeorm');
const Database = require('better-sqlite3');
const request = require('supertest');
const sharp = require('sharp');

function binaryParser(res, done) {
  const chunks = [];
  res.on('data', (chunk) => chunks.push(chunk));
  res.on('end', () => done(null, Buffer.concat(chunks)));
}

test('backup export verifies SHA-256, rejects concurrent exports, and restores cleanly onto a fresh volume', async (t) => {
  const dirA = mkdtempSync(join(tmpdir(), 'syncbox-vol-a-'));
  const dirB = mkdtempSync(join(tmpdir(), 'syncbox-vol-b-'));
  const prevDbPath = process.env.DATABASE_PATH;
  const prevNodeEnv = process.env.NODE_ENV;
  let appA;
  let appB;

  t.after(async () => {
    await appA?.close();
    await appB?.close();
    if (prevDbPath === undefined) delete process.env.DATABASE_PATH;
    else process.env.DATABASE_PATH = prevDbPath;
    if (prevNodeEnv === undefined) delete process.env.NODE_ENV;
    else process.env.NODE_ENV = prevNodeEnv;
    rmSync(dirA, { recursive: true, force: true });
    rmSync(dirB, { recursive: true, force: true });
  });

  process.env.NODE_ENV = 'test';
  process.env.DATABASE_PATH = join(dirA, 'syncbox.sqlite');
  const { AppModule } = require('../dist/app.module');
  const { configureApp } = require('../dist/app.setup');

  appA = await NestFactory.create(AppModule, new ExpressAdapter(), { logger: false });
  configureApp(appA);
  await appA.init();
  const apiA = request(appA.getHttpServer());

  const creds = { username: 'restore-owner', password: 'Restore-Password-2026' };
  const setup = (await apiA.post('/api/v1/auth/setup').send(creds).expect(201)).body;
  const auth = { Authorization: `Bearer ${setup.accessToken}` };

  const conv = (
    await apiA.post('/api/v1/conversations').set(auth).send({ title: '恢复演练会话' }).expect(201)
  ).body;
  const png = await sharp({ create: { width: 24, height: 24, channels: 3, background: '#2255aa' } })
    .png()
    .toBuffer();
  const payload = Buffer.from('important-backup-attachment-payload-2026');
  const attMsg = (
    await apiA
      .post(`/api/v1/conversations/${conv.id}/attachments`)
      .set(auth)
      .field('content', '附件消息')
      .field('names', JSON.stringify(['样本图.png', '备份文档.txt']))
      .attach('files', png, 'img.png')
      .attach('files', payload, 'doc.txt')
      .expect(201)
  ).body;
  await apiA
    .patch(`/api/v1/messages/${attMsg.id}`)
    .set(auth)
    .send({ annotation: '恢复核对批注', isStarred: true })
    .expect(200);

  // Concurrent backup calls: one succeeds (200) and concurrent one is rejected with 429.
  const [b1, b2] = await Promise.all([
    apiA.get('/api/v1/settings/backup').set(auth).buffer(true).parse(binaryParser),
    apiA.get('/api/v1/settings/backup').set(auth).buffer(true).parse(binaryParser),
  ]);
  const statuses = [b1.status, b2.status].sort();
  assert.deepEqual(statuses, [200, 429]);
  const okRes = b1.status === 200 ? b1 : b2;
  const expectedSha = okRes.headers['x-syncbox-backup-sha256'];
  assert.ok(expectedSha);
  const actualSha = createHash('sha256').update(okRes.body).digest('hex');
  assert.equal(actualSha, expectedSha);
  assert.equal(Number(okRes.headers['x-syncbox-backup-size']), okRes.body.length);

  // Stop service A before restoring onto volume B.
  await appA.close();
  appA = undefined;

  const restoredPath = join(dirB, 'syncbox.sqlite');
  writeFileSync(restoredPath, okRes.body);
  // Ensure clean state without stale WAL/SHM files.
  assert.equal(existsSync(restoredPath + '-wal'), false);
  assert.equal(existsSync(restoredPath + '-shm'), false);

  // Verify SQLite integrity before starting restored instance.
  const probe = new Database(restoredPath, { readonly: true });
  const integrity = probe.pragma('integrity_check', { simple: true });
  probe.close();
  assert.equal(integrity, 'ok');

  process.env.DATABASE_PATH = restoredPath;
  appB = await NestFactory.create(AppModule, new ExpressAdapter(), { logger: false });
  configureApp(appB);
  await appB.init();
  const apiB = request(appB.getHttpServer());

  // Existing session token in the snapshot works, and fresh login also works.
  await apiB.get('/api/v1/auth/me').set(auth).expect(200);
  const freshLogin = (await apiB.post('/api/v1/auth/login').send(creds).expect(200)).body;
  const authB = { Authorization: `Bearer ${freshLogin.accessToken}` };

  const convsB = (await apiB.get('/api/v1/conversations').set(authB).expect(200)).body;
  assert.equal(convsB.total, 1);
  assert.equal(convsB.items[0].title, '恢复演练会话');

  const starredB = (await apiB.get('/api/v1/messages/starred').set(authB).expect(200)).body;
  assert.equal(starredB.total, 1);
  assert.equal(starredB.items[0].annotation, '恢复核对批注');

  const downloadedDoc = await apiB
    .get(`/api/v1/messages/${attMsg.id}/attachments/${attMsg.attachments[1].id}`)
    .set(authB)
    .buffer(true)
    .parse(binaryParser)
    .expect(200);
  assert.deepEqual(downloadedDoc.body, payload);

  const downloadedPreview = await apiB
    .get(`/api/v1/messages/${attMsg.id}/attachments/${attMsg.attachments[0].id}/preview`)
    .set(authB)
    .buffer(true)
    .parse(binaryParser)
    .expect(200);
  assert.equal((await sharp(downloadedPreview.body).metadata()).format, 'webp');
  assert.equal(
    await appB
      .get(DataSource)
      .query('SELECT 1 AS ok')
      .then((r) => r[0].ok),
    1,
  );
});
