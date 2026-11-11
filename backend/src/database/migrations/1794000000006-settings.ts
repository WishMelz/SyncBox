import type { MigrationInterface, QueryRunner } from 'typeorm';
export class Settings1794000000006 implements MigrationInterface {
  async up(r: QueryRunner) {
    await r.query(`CREATE TABLE user_settings (
      user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
      cleanup_enabled INTEGER NOT NULL DEFAULT 0,
      idle_days INTEGER NOT NULL DEFAULT 30,
      last_cleanup_at INTEGER,
      last_cleanup_count INTEGER NOT NULL DEFAULT 0
    )`);
    for (const field of ['totp_secret', 'totp_pending', 'recovery_hashes'])
      await r.query(`ALTER TABLE users ADD COLUMN ${field} TEXT`);
    await r.query('ALTER TABLE users ADD COLUMN totp_pending_until INTEGER');
    await r.query('ALTER TABLE users ADD COLUMN totp_last_counter INTEGER NOT NULL DEFAULT -1');
    await r.query('ALTER TABLE messages ADD COLUMN files_expired INTEGER NOT NULL DEFAULT 0');
    for (const table of ['message_attachments', 'message_images']) {
      await r.query(`ALTER TABLE ${table} ADD COLUMN last_accessed_at INTEGER NOT NULL DEFAULT 0`);
      await r.query(`UPDATE ${table} SET last_accessed_at=?`, [Date.now()]);
    }
    await r.query('ALTER TABLE message_attachments ADD COLUMN deleted_at INTEGER');
    await r.query('CREATE INDEX attachments_access ON message_attachments(last_accessed_at)');
    await r.query('CREATE INDEX images_access ON message_images(last_accessed_at)');
  }
  async down(r: QueryRunner) {
    await r.query('DROP INDEX attachments_access');
    await r.query('DROP INDEX images_access');
    await r.query('ALTER TABLE message_attachments DROP COLUMN deleted_at');
    for (const table of ['message_attachments', 'message_images'])
      await r.query(`ALTER TABLE ${table} DROP COLUMN last_accessed_at`);
    await r.query('ALTER TABLE messages DROP COLUMN files_expired');
    for (const field of [
      'totp_secret',
      'totp_pending',
      'recovery_hashes',
      'totp_pending_until',
      'totp_last_counter',
    ])
      await r.query(`ALTER TABLE users DROP COLUMN ${field}`);
    await r.query('DROP TABLE user_settings');
  }
}
