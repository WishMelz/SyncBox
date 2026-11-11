import type { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * FTS5 is maintained as a small index table rather than an external-content
 * table so old databases can be rebuilt safely during migration.
 */
export class MessageSearch1794000000012 implements MigrationInterface {
  async up(runner: QueryRunner): Promise<void> {
    await runner.query(`CREATE VIRTUAL TABLE message_search USING fts5(
      message_id UNINDEXED, user_id UNINDEXED, conversation_id UNINDEXED,
      title, content, annotation, attachment_names,
      tokenize='unicode61 remove_diacritics 2'
    )`);
    await runner.query(`INSERT INTO message_search(message_id,user_id,conversation_id,title,content,annotation,attachment_names)
      SELECT m.id,m.user_id,m.conversation_id,m.title,m.content,m.annotation,
        COALESCE((SELECT group_concat(a.name, ' ') FROM message_attachments a WHERE a.message_id=m.id), '')
      FROM messages m`);
    await runner.query(`CREATE TRIGGER messages_search_insert AFTER INSERT ON messages BEGIN
      INSERT INTO message_search(message_id,user_id,conversation_id,title,content,annotation,attachment_names)
      VALUES (NEW.id,NEW.user_id,NEW.conversation_id,NEW.title,NEW.content,NEW.annotation,'');
    END`);
    await runner.query(`CREATE TRIGGER messages_search_update AFTER UPDATE OF title,content,annotation,conversation_id ON messages BEGIN
      DELETE FROM message_search WHERE message_id=NEW.id;
      INSERT INTO message_search(message_id,user_id,conversation_id,title,content,annotation,attachment_names)
      SELECT NEW.id,NEW.user_id,NEW.conversation_id,NEW.title,NEW.content,NEW.annotation,
        COALESCE((SELECT group_concat(a.name, ' ') FROM message_attachments a WHERE a.message_id=NEW.id), '');
    END`);
    await runner.query(`CREATE TRIGGER messages_search_delete AFTER DELETE ON messages BEGIN
      DELETE FROM message_search WHERE message_id=OLD.id;
    END`);
    for (const [name, event, id] of [
      ['message_search_attachment_insert', 'INSERT', 'NEW.message_id'],
      ['message_search_attachment_update', 'UPDATE OF name', 'NEW.message_id'],
      ['message_search_attachment_delete', 'DELETE', 'OLD.message_id'],
    ] as const) {
      await runner.query(`CREATE TRIGGER ${name} AFTER ${event} ON message_attachments BEGIN
        DELETE FROM message_search WHERE message_id=${id};
        INSERT INTO message_search(message_id,user_id,conversation_id,title,content,annotation,attachment_names)
        SELECT m.id,m.user_id,m.conversation_id,m.title,m.content,m.annotation,
          COALESCE((SELECT group_concat(a.name, ' ') FROM message_attachments a WHERE a.message_id=m.id), '')
        FROM messages m WHERE m.id=${id};
      END`);
    }
  }

  async down(runner: QueryRunner): Promise<void> {
    await runner.query('DROP TRIGGER message_search_attachment_delete');
    await runner.query('DROP TRIGGER message_search_attachment_update');
    await runner.query('DROP TRIGGER message_search_attachment_insert');
    await runner.query('DROP TRIGGER messages_search_delete');
    await runner.query('DROP TRIGGER messages_search_update');
    await runner.query('DROP TRIGGER messages_search_insert');
    await runner.query('DROP TABLE message_search');
  }
}
