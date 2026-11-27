import type { MigrationInterface, QueryRunner } from 'typeorm';

export class UnreadPartialIndex1794000000013 implements MigrationInterface {
  async up(runner: QueryRunner): Promise<void> {
    await runner.query(
      'CREATE INDEX IF NOT EXISTS messages_conversation_unread ON messages(conversation_id) WHERE is_read = 0',
    );
  }

  async down(runner: QueryRunner): Promise<void> {
    await runner.query('DROP INDEX IF EXISTS messages_conversation_unread');
  }
}
