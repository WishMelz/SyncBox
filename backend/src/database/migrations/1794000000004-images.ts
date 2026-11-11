import type { MigrationInterface, QueryRunner } from 'typeorm';
export class Images1794000000004 implements MigrationInterface {
  async up(queryRunner: QueryRunner) {
    await queryRunner.query(`CREATE TABLE message_images (
      message_id TEXT PRIMARY KEY REFERENCES messages(id) ON DELETE CASCADE,
      mime_type TEXT NOT NULL,
      width INTEGER NOT NULL,
      height INTEGER NOT NULL,
      size INTEGER NOT NULL,
      data BLOB NOT NULL
    )`);
  }
  async down(queryRunner: QueryRunner) {
    await queryRunner.query('DROP TABLE message_images');
  }
}
