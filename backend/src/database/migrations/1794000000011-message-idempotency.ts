import type { MigrationInterface, QueryRunner } from 'typeorm';

export class MessageIdempotency1794000000011 implements MigrationInterface {
  async up(runner: QueryRunner): Promise<void> {
    await runner.query('ALTER TABLE messages ADD COLUMN client_id TEXT');
    await runner.query(
      'CREATE UNIQUE INDEX messages_user_client ON messages(user_id, client_id) WHERE client_id IS NOT NULL',
    );
  }

  async down(runner: QueryRunner): Promise<void> {
    await runner.query('DROP INDEX messages_user_client');
    await runner.query('ALTER TABLE messages DROP COLUMN client_id');
  }
}
