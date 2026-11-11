import type { MigrationInterface, QueryRunner } from 'typeorm';
export class Pinned1794000000007 implements MigrationInterface {
  async up(r: QueryRunner) {
    await r.query('ALTER TABLE conversations ADD COLUMN is_pinned INTEGER NOT NULL DEFAULT 0');
    await r.query(
      'CREATE INDEX conversations_pinned ON conversations(user_id,is_pinned,updated_at DESC)',
    );
  }
  async down(r: QueryRunner) {
    await r.query('DROP INDEX conversations_pinned');
    await r.query('ALTER TABLE conversations DROP COLUMN is_pinned');
  }
}
