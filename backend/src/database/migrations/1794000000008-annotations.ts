import type { MigrationInterface, QueryRunner } from 'typeorm';

export class Annotations1794000000008 implements MigrationInterface {
  async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query("ALTER TABLE messages ADD COLUMN annotation TEXT NOT NULL DEFAULT ''");
  }
  async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query('ALTER TABLE messages DROP COLUMN annotation');
  }
}
