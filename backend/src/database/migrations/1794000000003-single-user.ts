import type { MigrationInterface, QueryRunner } from 'typeorm';
export class SingleUser1794000000003 implements MigrationInterface {
  async up(r: QueryRunner) {
    const [row] = await r.query('SELECT COUNT(*) AS total FROM users');
    if (row.total > 1)
      throw new Error(
        'Single-user migration requires one account or fewer. Back up the database and resolve existing accounts before upgrading; no data has been deleted.',
      );
    await r.query('ALTER TABLE users ADD COLUMN username TEXT');
    await r.query('UPDATE users SET username = email');
    await r.query('CREATE UNIQUE INDEX users_username ON users(username COLLATE NOCASE)');
    await r.query('CREATE UNIQUE INDEX users_singleton ON users((1))');
  }
  async down(r: QueryRunner) {
    await r.query('DROP INDEX users_singleton');
    await r.query('DROP INDEX users_username');
    await r.query('ALTER TABLE users DROP COLUMN username');
  }
}
