import type { MigrationInterface, QueryRunner } from 'typeorm';
export class Attachments1794000000005 implements MigrationInterface {
  async up(r: QueryRunner) {
    await r.query(`CREATE TABLE message_attachments (
      id TEXT PRIMARY KEY,
      message_id TEXT NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
      position INTEGER NOT NULL,
      name TEXT NOT NULL,
      mime_type TEXT NOT NULL,
      size INTEGER NOT NULL,
      data BLOB NOT NULL,
      preview BLOB,
      width INTEGER,
      height INTEGER
    )`);
    await r.query('CREATE INDEX attachments_message ON message_attachments(message_id,position)');
  }
  async down(r: QueryRunner) {
    await r.query('DROP TABLE message_attachments');
  }
}
