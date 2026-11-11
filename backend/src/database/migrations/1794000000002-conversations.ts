import { randomUUID } from 'node:crypto';
import type { MigrationInterface, QueryRunner } from 'typeorm';
export class Conversations1794000000002 implements MigrationInterface {
  async up(r: QueryRunner) {
    await r.query(
      `CREATE TABLE conversations (id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE, title TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)`,
    );
    await r.query('CREATE INDEX conversations_owner ON conversations(user_id,updated_at DESC)');
    await r.query(
      'ALTER TABLE messages ADD COLUMN conversation_id TEXT REFERENCES conversations(id) ON DELETE CASCADE',
    );
    const owners = await r.query('SELECT DISTINCT user_id FROM messages');
    for (const { user_id } of owners) {
      const id = randomUUID(),
        now = new Date().toISOString();
      await r.query('INSERT INTO conversations VALUES (?,?,?,?,?)', [
        id,
        user_id,
        '历史消息',
        now,
        now,
      ]);
      await r.query('UPDATE messages SET conversation_id = ? WHERE user_id = ?', [id, user_id]);
    }
    await r.query(
      'CREATE INDEX messages_conversation ON messages(conversation_id,created_at DESC,id DESC)',
    );
  }
  async down(r: QueryRunner) {
    await r.query('DROP INDEX messages_conversation');
    await r.query('ALTER TABLE messages DROP COLUMN conversation_id');
    await r.query('DROP TABLE conversations');
  }
}
