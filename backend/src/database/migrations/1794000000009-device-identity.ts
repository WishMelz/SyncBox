import type { MigrationInterface, QueryRunner } from 'typeorm';
export class DeviceIdentity1794000000009 implements MigrationInterface {
  async up(runner: QueryRunner): Promise<void> {
    await runner.query('ALTER TABLE devices ADD COLUMN installation_hash TEXT');
    await runner.query('ALTER TABLE devices ADD COLUMN fingerprint_hash TEXT');
    await runner.query(
      'CREATE UNIQUE INDEX devices_installation ON devices(user_id,platform,installation_hash) WHERE installation_hash IS NOT NULL',
    );
  }
  async down(runner: QueryRunner): Promise<void> {
    await runner.query('DROP INDEX devices_installation');
    await runner.query('ALTER TABLE devices DROP COLUMN fingerprint_hash');
    await runner.query('ALTER TABLE devices DROP COLUMN installation_hash');
  }
}
