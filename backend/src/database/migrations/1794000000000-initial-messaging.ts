import type { MigrationInterface, QueryRunner } from 'typeorm';

export class InitialMessaging1794000000000 implements MigrationInterface {
  async up(runner: QueryRunner): Promise<void> {
    await runner.query(`CREATE TABLE users (
      id TEXT PRIMARY KEY, email TEXT NOT NULL UNIQUE, name TEXT NOT NULL,
      password_hash TEXT NOT NULL, created_at TEXT NOT NULL
    )`);
    await runner.query(`CREATE TABLE sessions (
      token_hash TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      expires_at INTEGER NOT NULL
    )`);
    await runner.query('CREATE INDEX sessions_expiry ON sessions(expires_at)');
    await runner.query(`CREATE TABLE messages (
      id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      title TEXT NOT NULL, content TEXT NOT NULL, source TEXT NOT NULL,
      is_read INTEGER NOT NULL DEFAULT 0, is_starred INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL
    )`);
    await runner.query(
      'CREATE INDEX messages_user_created ON messages(user_id, created_at DESC, id DESC)',
    );
  }
  async down(runner: QueryRunner): Promise<void> {
    await runner.query('DROP TABLE messages');
    await runner.query('DROP TABLE sessions');
    await runner.query('DROP TABLE users');
  }
}
