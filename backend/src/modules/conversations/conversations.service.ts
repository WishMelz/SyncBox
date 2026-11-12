import { Injectable, NotFoundException } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { DatabaseService } from '../../database/database.service';

function ftsQuery(value: string) {
  return value
    .trim()
    .split(/\s+/)
    .filter(Boolean)
    .map((term) => `"${term.replaceAll('"', '""')}"*`)
    .join(' AND ');
}
function canUseFts(value: string) {
  return /[\p{L}\p{N}]/u.test(value) && !/[\%_]/.test(value);
}
@Injectable()
export class ConversationsService {
  constructor(private readonly db: DatabaseService) {}
  async create(userId: string, title: string) {
    const id = randomUUID(),
      now = new Date().toISOString();
    await this.db.query(
      'INSERT INTO conversations (id,user_id,title,created_at,updated_at) VALUES (?,?,?,?,?)',
      [id, userId, title, now, now],
    );
    return this.detail(userId, id);
  }
  async detail(userId: string, id: string) {
    const rows = await this.db.query(
      'SELECT id,title,is_pinned AS isPinned,created_at AS createdAt,updated_at AS updatedAt FROM conversations WHERE id = ? AND user_id = ?',
      [id, userId],
    );
    if (!rows[0]) throw new NotFoundException('会话不存在');
    return { ...rows[0], isPinned: !!rows[0].isPinned };
  }
  async list(userId: string, q: string, page: number, pageSize: number) {
    const term = '%' + q.replace(/[\\%_]/g, '\\$&') + '%';
    const where = canUseFts(q)
      ? "c.user_id = ? AND (c.title LIKE ? ESCAPE '\\' OR EXISTS (SELECT 1 FROM messages m WHERE m.conversation_id = c.id AND m.id IN (SELECT message_id FROM message_search WHERE message_search MATCH ?)))"
      : "c.user_id = ? AND (c.title LIKE ? ESCAPE '\\' OR EXISTS (SELECT 1 FROM messages m WHERE m.conversation_id = c.id AND (m.annotation LIKE ? ESCAPE '\\' OR m.content LIKE ? ESCAPE '\\' OR EXISTS (SELECT 1 FROM message_attachments a WHERE a.message_id=m.id AND a.name LIKE ? ESCAPE '\\'))))";
    const searchArgs = canUseFts(q)
      ? [userId, term, ftsQuery(q)]
      : [userId, term, term, term, term];
    return this.db.transaction(async (manager) => {
      const [count] = await manager.query(
        `SELECT COUNT(*) AS total FROM conversations c WHERE ${where}`,
        searchArgs,
      );
      const items = await manager.query(
        `SELECT c.id,c.title,c.is_pinned AS isPinned,c.created_at AS createdAt,c.updated_at AS updatedAt,(SELECT COUNT(*) FROM messages m WHERE m.conversation_id=c.id) AS messageCount,(SELECT COUNT(*) FROM messages m WHERE m.conversation_id=c.id AND m.is_read=0) AS unreadCount,(SELECT substr(content,1,100) FROM messages m WHERE m.conversation_id=c.id ORDER BY created_at DESC,id DESC LIMIT 1) AS preview FROM conversations c WHERE ${where} ORDER BY c.is_pinned DESC,c.updated_at DESC,c.id DESC LIMIT ? OFFSET ?`,
        [...searchArgs, pageSize, (page - 1) * pageSize],
      );
      return {
        items: items.map((item: { isPinned: number }) => ({ ...item, isPinned: !!item.isPinned })),
        total: count.total,
        page,
        pageSize,
        totalPages: Math.ceil(count.total / pageSize),
      };
    });
  }
  async markRead(userId: string, id: string) {
    await this.detail(userId, id);
    await this.db.query(
      'UPDATE messages SET is_read=1 WHERE user_id=? AND conversation_id=? AND is_read=0',
      [userId, id],
    );
  }
  async update(userId: string, id: string, dto: { title?: string; pinned?: boolean }) {
    await this.detail(userId, id);
    const fields: string[] = [],
      args: unknown[] = [];
    if (dto.title !== undefined) {
      fields.push('title=?');
      args.push(dto.title);
    }
    if (dto.pinned !== undefined) {
      fields.push('is_pinned=?');
      args.push(dto.pinned ? 1 : 0);
    }
    if (!fields.length) return this.detail(userId, id);
    if (dto.title !== undefined) {
      fields.push('updated_at=?');
      args.push(new Date().toISOString());
    }
    await this.db.query(`UPDATE conversations SET ${fields.join(',')} WHERE id=? AND user_id=?`, [
      ...args,
      id,
      userId,
    ]);
    return this.detail(userId, id);
  }
  async rename(userId: string, id: string, title: string) {
    return this.update(userId, id, { title });
  }
  async remove(userId: string, id: string) {
    await this.detail(userId, id);
    await this.db.query('DELETE FROM conversations WHERE id=? AND user_id=?', [id, userId]);
  }
}
