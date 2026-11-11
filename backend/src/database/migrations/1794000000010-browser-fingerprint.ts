import type { MigrationInterface, QueryRunner } from 'typeorm';

export class BrowserFingerprint1794000000010 implements MigrationInterface {
  async up(runner: QueryRunner): Promise<void> {
    // Keep old environment hints separate: they were never intended to identify a browser.
    await runner.query('ALTER TABLE devices ADD COLUMN browser_fingerprint_hash TEXT');
    await runner.query(
      'CREATE UNIQUE INDEX devices_browser_fingerprint ON devices(user_id,browser_fingerprint_hash) WHERE browser_fingerprint_hash IS NOT NULL',
    );
  }

  async down(runner: QueryRunner): Promise<void> {
    await runner.query('DROP INDEX devices_browser_fingerprint');
    await runner.query('ALTER TABLE devices DROP COLUMN browser_fingerprint_hash');
  }
}
