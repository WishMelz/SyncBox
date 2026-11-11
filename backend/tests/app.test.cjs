const { test } = require('node:test');
const assert = require('node:assert/strict');
const { mkdtemp, rm } = require('node:fs/promises');
const { tmpdir } = require('node:os');
const { join } = require('node:path');
const request = require('supertest');
const { NestFactory } = require('@nestjs/core');
const { ExpressAdapter } = require('@nestjs/platform-express');
const { DataSource } = require('typeorm');
const { validateEnvironment } = require('../dist/config/env');

test('configuration rejects invalid values', () => {
  for (const PORT of ['', '0', '65536', '12abc', '3.5']) {
    assert.throws(() => validateEnvironment({ PORT }), /PORT/);
  }
  assert.throws(() => validateEnvironment({ DATABASE_PATH: ' ' }), /DATABASE_PATH/);
  assert.throws(() => validateEnvironment({ NODE_ENV: 'invalid' }), /NODE_ENV/);
});

test('Nest API checks SQLite, handles unknown routes, and retains data after reconnect', async (t) => {
  const directory = await mkdtemp(join(tmpdir(), 'syncbox-test-'));
  const previousPath = process.env.DATABASE_PATH;
  process.env.DATABASE_PATH = join(directory, 'test.sqlite');
  t.after(async () => {
    if (previousPath === undefined) delete process.env.DATABASE_PATH;
    else process.env.DATABASE_PATH = previousPath;
    await rm(directory, { recursive: true, force: true });
  });
  const { AppModule } = require('../dist/app.module');
  const { configureApp } = require('../dist/app.setup');
  const app = await NestFactory.create(AppModule, new ExpressAdapter(), {
    logger: false,
    abortOnError: false,
  });
  t.after(() => app.close());
  configureApp(app);
  await app.init();
  const health = await request(app.getHttpServer()).get('/api/v1/health').expect(200);
  assert.deepEqual(health.body, { status: 'ok', service: 'syncbox-backend', database: 'up' });
  await request(app.getHttpServer()).get('/api/v1/missing').expect(404);
  const db = app.get(DataSource);
  await db.query('CREATE TABLE persistence_probe (value TEXT NOT NULL)');
  await db.query('INSERT INTO persistence_probe (value) VALUES (?)', ['retained']);
  await db.destroy();
  await request(app.getHttpServer()).get('/api/v1/health').expect(503);
  await db.initialize();
  assert.deepEqual(await db.query('SELECT value FROM persistence_probe'), [{ value: 'retained' }]);
  await request(app.getHttpServer()).get('/api/v1/health').expect(200);
});
