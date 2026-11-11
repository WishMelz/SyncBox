import type { MigrationInterface, QueryRunner } from 'typeorm';
export class Devices1794000000001 implements MigrationInterface {
  async up(runner: QueryRunner): Promise<void> {
    await runner.query(`CREATE TABLE devices (
      id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      name TEXT NOT NULL, platform TEXT NOT NULL, created_at TEXT NOT NULL, last_seen_at TEXT NOT NULL
    )`);
    await runner.query('CREATE INDEX devices_user ON devices(user_id)');
    await runner.query(
      'ALTER TABLE sessions ADD COLUMN device_id TEXT REFERENCES devices(id) ON DELETE SET NULL',
    );
    await runner.query(
      'ALTER TABLE messages ADD COLUMN sender_device_id TEXT REFERENCES devices(id) ON DELETE SET NULL',
    );
    await runner.query('ALTER TABLE messages ADD COLUMN sender_device_name TEXT');
    await runner.query('ALTER TABLE messages ADD COLUMN sender_device_platform TEXT');
  }
  async down(runner: QueryRunner): Promise<void> {
    await runner.query('ALTER TABLE messages DROP COLUMN sender_device_platform');
    await runner.query('ALTER TABLE messages DROP COLUMN sender_device_name');
    await runner.query('ALTER TABLE messages DROP COLUMN sender_device_id');
    await runner.query('ALTER TABLE sessions DROP COLUMN device_id');
    await runner.query('DROP TABLE devices');
  }
}
