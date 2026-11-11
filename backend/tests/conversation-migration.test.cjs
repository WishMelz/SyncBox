const { test } = require('node:test');
const assert = require('node:assert/strict');
const { DataSource } = require('typeorm');
const {
  InitialMessaging1794000000000,
} = require('../dist/database/migrations/1794000000000-initial-messaging');
const { Devices1794000000001 } = require('../dist/database/migrations/1794000000001-devices');
const {
  Conversations1794000000002,
} = require('../dist/database/migrations/1794000000002-conversations');
test('existing user messages migrate into separate history conversations without content loss', async (t) => {
  const db = new DataSource({
    type: 'better-sqlite3',
    database: ':memory:',
    migrations: [InitialMessaging1794000000000, Devices1794000000001],
  });
  await db.initialize();
  t.after(() => db.destroy());
  await db.runMigrations();
  for (const id of ['one', 'two']) {
    await db.query('INSERT INTO users VALUES (?,?,?,?,?)', [
      id,
      id + '@example.com',
      id,
      'hashed',
      '2026-01-01',
    ]);
    await db.query(
      'INSERT INTO messages (id,user_id,title,content,source,created_at,updated_at) VALUES (?,?,?,?,?,?,?)',
      [id, id, 'Original', 'Preserve ' + id, 'manual', '2026-01-01', '2026-01-01'],
    );
  }
  const runner = db.createQueryRunner();
  await new Conversations1794000000002().up(runner);
  const rows = await db.query(
    'SELECT m.content,c.user_id,c.title FROM messages m JOIN conversations c ON c.id=m.conversation_id ORDER BY m.id',
  );
  assert.deepEqual(rows, [
    { content: 'Preserve one', user_id: 'one', title: '历史消息' },
    { content: 'Preserve two', user_id: 'two', title: '历史消息' },
  ]);
  await runner.release();
});
