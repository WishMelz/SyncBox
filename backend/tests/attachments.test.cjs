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
const { safeFilename } = require('../dist/modules/messages/attachments');
const { ATTACHMENT_LIMIT } = require('../dist/modules/messages/attachments');

function binaryParser(res, done) {
  const chunks = [];
  res.on('data', (chunk) => chunks.push(chunk));
  res.on('end', () => done(null, Buffer.concat(chunks)));
}

test('multiple attachments retain original bytes, safe downloads, authenticated previews and filename search', async (t) => {
  const app = await NestFactory.create(AppModule, new ExpressAdapter(), { logger: false });
  t.after(() => app.close());
  configureApp(app);
  await app.init();
  const api = request(app.getHttpServer()),
    db = app.get(DataSource);
  const session = await api
    .post('/api/v1/auth/setup')
    .send({ username: 'files-test', password: '123456' })
    .expect(201);
  const auth = { Authorization: `Bearer ${session.body.accessToken}` };
  const c = await api.post('/api/v1/conversations').set(auth).send({ title: 'Files' }).expect(201);
  const path = `/api/v1/conversations/${c.body.id}/attachments`;
  const png = await sharp({ create: { width: 64, height: 32, channels: 3, background: '#457963' } })
    .png()
    .toBuffer();
  const document = Buffer.from('附件内容\n原样保留 %_');
  const html = Buffer.from('<script>alert(document.cookie)</script>');
  const sent = await api
    .post(path)
    .set(auth)
    .field('content', '项目资料')
    .field('names', JSON.stringify(['设计图.png', '需求 100%_最终.txt', '页面.html']))
    .attach('files', png, 'upload')
    .attach('files', document, 'upload')
    .attach('files', html, { filename: 'upload', contentType: 'text/html' })
    .expect(201);
  assert.equal(sent.body.content, '项目资料');
  assert.equal(sent.body.attachments.length, 3);
  assert.equal(sent.body.image, null);
  const [image, text, active] = sent.body.attachments;
  assert.deepEqual(
    [image.name, text.name, active.name],
    ['设计图.png', '需求 100%_最终.txt', '页面.html'],
  );
  assert.equal(image.hasPreview, true);
  assert.equal(text.hasPreview, false);
  assert.equal(active.hasPreview, false);
  assert.equal(image.width, 64);
  assert.equal(text.size, document.length);
  assert.equal('data' in image, false);
  for (const [attachment, original] of [
    [image, png],
    [text, document],
    [active, html],
  ]) {
    const url = `/api/v1/messages/${sent.body.id}/attachments/${attachment.id}`;
    await api.get(url).expect(401);
    const result = await api
      .get(url)
      .set(auth)
      .buffer(true)
      .parse(binaryParser)
      .expect(200)
      .expect('Content-Type', /application\/octet-stream/)
      .expect('Content-Disposition', /^attachment;/)
      .expect('Cache-Control', 'no-store')
      .expect('X-Content-Type-Options', 'nosniff');
    assert.deepEqual(result.body, original);
    assert.ok(result.headers['content-disposition'].includes(encodeURIComponent(attachment.name)));
  }
  const preview = `/api/v1/messages/${sent.body.id}/attachments/${image.id}/preview`;
  await api.get(preview).expect(401);
  const previewResponse = await api
    .get(preview)
    .set(auth)
    .expect(200)
    .expect('Content-Type', /image\/webp/);
  assert.equal((await sharp(previewResponse.body).metadata()).format, 'webp');
  await api
    .get(`/api/v1/messages/${sent.body.id}/attachments/${active.id}/preview`)
    .set(auth)
    .expect(404);
  const other = await api
    .post(`/api/v1/conversations/${c.body.id}/messages`)
    .set(auth)
    .send({ content: 'plain' })
    .expect(201);
  await api.get(`/api/v1/messages/${other.body.id}/attachments/${text.id}`).set(auth).expect(404);
  const search = encodeURIComponent('100%_最终');
  const history = await api
    .get(`/api/v1/conversations/${c.body.id}/messages?q=${search}`)
    .set(auth)
    .expect(200);
  assert.equal(history.body.total, 1);
  assert.deepEqual(history.body.items[0].attachments, sent.body.attachments);
  const conversations = await api.get(`/api/v1/conversations?q=${search}`).set(auth).expect(200);
  assert.equal(conversations.body.total, 1);
  const detail = await api.get(`/api/v1/messages/${sent.body.id}`).set(auth).expect(200);
  assert.deepEqual(detail.body.attachments, sent.body.attachments);
  const plain = await api.get(`/api/v1/messages/${other.body.id}`).set(auth).expect(200);
  assert.deepEqual(plain.body.attachments, []);
  await api.delete(`/api/v1/messages/${sent.body.id}`).set(auth).expect(204);
  assert.equal((await db.query('SELECT COUNT(*) n FROM message_attachments'))[0].n, 0);
  await api.get(preview).set(auth).expect(404);
  const withoutCaption = await api
    .post(path)
    .set(auth)
    .attach('files', document, 'notes.txt')
    .expect(201);
  assert.match(withoutCaption.body.content, /^\[附件\] notes.txt/);
  await api.delete(`/api/v1/conversations/${c.body.id}`).set(auth).expect(204);
  assert.equal((await db.query('SELECT COUNT(*) n FROM message_attachments'))[0].n, 0);
});

test('attachment limits and invalid manifests do not create partial messages', async (t) => {
  const app = await NestFactory.create(AppModule, new ExpressAdapter(), { logger: false });
  t.after(() => app.close());
  configureApp(app);
  await app.init();
  const api = request(app.getHttpServer()),
    db = app.get(DataSource);
  const session = await api
    .post('/api/v1/auth/setup')
    .send({ username: 'limits-test', password: '123456' })
    .expect(201);
  const auth = { Authorization: `Bearer ${session.body.accessToken}` };
  const c = await api.post('/api/v1/conversations').set(auth).send({ title: 'Limits' }).expect(201);
  const path = `/api/v1/conversations/${c.body.id}/attachments`;
  await api.post(path).attach('files', Buffer.from('a'), 'a.txt').expect(401);
  await api.post(path).set(auth).send({ content: 'no files' }).expect(400);
  await api.post(path).set(auth).attach('files', Buffer.alloc(0), 'empty.txt').expect(400);
  let six = api.post(path).set(auth);
  for (let i = 0; i < 6; i++) six = six.attach('files', Buffer.from('a'), `${i}.txt`);
  await six.expect(400);
  await api
    .post(path)
    .set(auth)
    .attach('files', Buffer.alloc(ATTACHMENT_LIMIT + 1), 'large.bin')
    .expect(413);
  await api
    .post(path)
    .set(auth)
    .attach('files', Buffer.alloc(11 * 1024 * 1024), 'a.bin')
    .attach('files', Buffer.alloc(10 * 1024 * 1024), 'b.bin')
    .expect(413);
  for (const names of ['invalid-json', '[]', '[12]'])
    await api
      .post(path)
      .set(auth)
      .field('names', names)
      .attach('files', Buffer.from('a'), 'a.txt')
      .expect(400);
  await api
    .post('/api/v1/conversations/00000000-0000-4000-8000-000000000000/attachments')
    .set(auth)
    .attach('files', Buffer.from('a'), 'a.txt')
    .expect(404);
  assert.equal((await db.query('SELECT COUNT(*) n FROM messages'))[0].n, 0);
  assert.equal((await db.query('SELECT COUNT(*) n FROM message_attachments'))[0].n, 0);
  assert.equal(safeFilename('../folder/evil\r\nname.txt'), 'evilname.txt');
  assert.equal(safeFilename('..\\..\\报告.txt'), '报告.txt');
  assert.equal(safeFilename('..'), 'attachment');
  assert.ok(!safeFilename('x\u202egpj.exe').includes('\u202e'));
  let five = api
    .post(path)
    .set(auth)
    .field('content', 'Five files')
    .field('names', JSON.stringify(['1.txt', '2.txt', '3.txt', '4.txt', '5.txt']));
  for (let i = 0; i < 5; i++) five = five.attach('files', Buffer.from('a'), 'upload');
  const maximumCount = await five.expect(201);
  assert.equal(maximumCount.body.attachments.length, 5);
  await api
    .post(path)
    .set(auth)
    .attach('files', Buffer.alloc(ATTACHMENT_LIMIT), 'exact-limit.bin')
    .expect(201);
});
