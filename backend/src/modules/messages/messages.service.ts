import { attachmentMetadataSQL, prepareAttachments, type AttachmentUpload } from './attachments';
import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { DatabaseService } from '../../database/database.service';
import { randomUUID } from 'node:crypto';
import sharp from 'sharp';
import { CreateMessageDto, ListFilesDto, ListMessagesDto, UpdateMessageDto } from './messages.dto';
interface ImageUpload {
  data: Buffer;
  mimeType: string;
  width: number;
  height: number;
}
interface MessageRow {
  conversation_title?: string;
  attachments_json?: string;
  files_expired?: number;
  mime_type?: string;
  width?: number;
  height?: number;
  size?: number;
  id: string;
  conversation_id: string;
  title: string;
  content: string;
  annotation: string;
  source: string;
  is_read: number;
  is_starred: number;
  created_at: string;
  updated_at: string;
  sender_device_id: string | null;
  sender_device_name: string | null;
  sender_device_platform: string | null;
}
const serialize = (row: MessageRow) => ({
  id: row.id,
  conversationId: row.conversation_id,
  conversationTitle: row.conversation_title,
  filesExpired: !!row.files_expired,
  attachments: JSON.parse(row.attachments_json ?? '[]'),
  image: row.mime_type
    ? { mimeType: row.mime_type, width: row.width, height: row.height, size: row.size }
    : null,
  title: row.title,
  content: row.content,
  annotation: row.annotation,
  source: row.source,
  isRead: Boolean(row.is_read),
  isStarred: Boolean(row.is_starred),
  createdAt: row.created_at,
  updatedAt: row.updated_at,
  senderDevice: row.sender_device_name
    ? {
        id: row.sender_device_id,
        name: row.sender_device_name,
        platform: row.sender_device_platform,
      }
    : null,
});

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
export class MessagesService {
  constructor(private readonly db: DatabaseService) {}
  async create(
    userId: string,
    dto: CreateMessageDto,
    deviceId?: string | null,
    conversationId?: string,
    image?: ImageUpload,
    attachments: AttachmentUpload[] = [],
  ) {
    const id = randomUUID();
    let existingId: string | undefined;
    const now = new Date().toISOString();
    await this.db.transaction(async (manager) => {
      if (dto.clientId) {
        const existing = await manager.query(
          'SELECT id FROM messages WHERE user_id=? AND client_id=? LIMIT 1',
          [userId, dto.clientId],
        );
        if (existing[0]) {
          existingId = existing[0].id as string;
          return;
        }
      }
      if (!conversationId) {
        const existing = await manager.query(
          'SELECT id FROM conversations WHERE user_id=? AND title=? LIMIT 1',
          [userId, '临时传输'],
        );
        conversationId = existing[0]?.id ?? randomUUID();
        if (!existing[0])
          await manager.query(
            'INSERT INTO conversations (id,user_id,title,created_at,updated_at) VALUES (?,?,?,?,?)',
            [conversationId, userId, '临时传输', now, now],
          );
      }
      const owned = await manager.query('SELECT id FROM conversations WHERE id=? AND user_id=?', [
        conversationId,
        userId,
      ]);
      if (!owned[0]) throw new NotFoundException('会话不存在');
      await manager.query('UPDATE conversations SET updated_at=? WHERE id=?', [
        now,
        conversationId,
      ]);
      const devices = deviceId
        ? await manager.query('SELECT id,name,platform FROM devices WHERE id = ? AND user_id = ?', [
            deviceId,
            userId,
          ])
        : [];
      const device = devices[0];
      await manager.query(
        'INSERT INTO messages (id,user_id,title,content,source,created_at,updated_at,sender_device_id,sender_device_name,sender_device_platform,conversation_id,client_id) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)',
        [
          id,
          userId,
          dto.title,
          dto.content,
          dto.source,
          now,
          now,
          device?.id ?? null,
          device?.name ?? null,
          device?.platform ?? null,
          conversationId,
          dto.clientId ?? null,
        ],
      );
      for (const [position, file] of attachments.entries()) {
        await manager.query(
          'INSERT INTO message_attachments (id,message_id,position,name,mime_type,size,data,preview,width,height,last_accessed_at) VALUES (?,?,?,?,?,?,?,?,?,?,?)',
          [
            file.id,
            id,
            position,
            file.name,
            file.mimeType,
            file.data.length,
            file.data,
            file.preview,
            file.width,
            file.height,
            Date.now(),
          ],
        );
      }
      if (image) {
        await manager.query(
          'INSERT INTO message_images (message_id,mime_type,width,height,size,data,last_accessed_at) VALUES (?,?,?,?,?,?,?)',
          [
            id,
            image.mimeType,
            image.width,
            image.height,
            image.data.length,
            image.data,
            Date.now(),
          ],
        );
      }
    });
    return this.detail(userId, existingId ?? id);
  }
  async list(userId: string, query: ListMessagesDto, conversationId?: string, fullContent = false) {
    const cursor = (value: string | undefined) => {
      if (value === undefined) return undefined;
      const match =
        /^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z)\|([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$/i.exec(
          value,
        );
      if (
        !match ||
        !Number.isFinite(Date.parse(match[1]!)) ||
        new Date(match[1]!).toISOString() !== match[1]
      ) {
        throw new BadRequestException('消息游标无效，请刷新后重试');
      }
      return [match[1]!, match[2]!.toLowerCase()] as const;
    };
    const before = cursor(query.before),
      since = cursor(query.since);
    if ((before || since) && query.page !== 1)
      throw new BadRequestException('加载历史消息时页码必须为 1');
    const clauses = ['user_id = ?'];
    const args: unknown[] = [userId];
    if (conversationId) {
      clauses.push('conversation_id = ?');
      args.push(conversationId);
    }
    if (query.q) {
      const term = `%${query.q.replace(/[\\%_]/g, '\\$&')}%`;
      if (canUseFts(query.q)) {
        clauses.push(
          'messages.id IN (SELECT message_id FROM message_search WHERE message_search MATCH ?)',
        );
        args.push(ftsQuery(query.q));
      } else {
        clauses.push(
          "(title LIKE ? ESCAPE '\\' OR annotation LIKE ? ESCAPE '\\' OR content LIKE ? ESCAPE '\\' OR EXISTS (SELECT 1 FROM message_attachments a WHERE a.message_id=messages.id AND a.name LIKE ? ESCAPE '\\'))",
        );
        args.push(term, term, term, term);
      }
    }
    if (query.source) {
      clauses.push('source = ?');
      args.push(query.source);
    }
    for (const [field, value] of [
      ['is_read', query.isRead],
      ['is_starred', query.isStarred],
    ]) {
      if (value !== undefined) {
        clauses.push(`${field} = ?`);
        args.push(value === 'true' ? 1 : 0);
      }
    }
    const where = clauses.join(' AND ');
    const rangeClauses = [...clauses],
      rangeArgs = [...args];
    if (before) {
      rangeClauses.push('(created_at < ? OR (created_at = ? AND id < ?))');
      rangeArgs.push(before[0], before[0], before[1]);
    }
    if (since) {
      rangeClauses.push('(created_at > ? OR (created_at = ? AND id >= ?))');
      rangeArgs.push(since[0], since[0], since[1]);
    }
    return this.db.transaction(async (manager) => {
      const [count]: { total: number }[] = await manager.query(
        `SELECT COUNT(*) AS total FROM messages WHERE ${where}`,
        args,
      );
      const rows: MessageRow[] = await manager.query(
        `SELECT messages.*, (SELECT c.title FROM conversations c WHERE c.id=messages.conversation_id AND c.user_id=messages.user_id) AS conversation_title, ${attachmentMetadataSQL} AS attachments_json, i.mime_type, i.width, i.height, i.size FROM messages LEFT JOIN message_images i ON i.message_id=messages.id WHERE ${rangeClauses.join(' AND ')} ORDER BY created_at DESC, id DESC LIMIT ? OFFSET ?`,
        [...rangeArgs, query.pageSize + 1, (query.page - 1) * query.pageSize],
      );
      const total = count?.total ?? 0;
      const visible = rows.slice(0, query.pageSize),
        last = visible.at(-1);
      const hasMore = rows.length > query.pageSize;
      return {
        items: visible.map((row) => {
          if (conversationId || fullContent) return serialize(row);
          const { content, ...item } = serialize(row);
          return { ...item, preview: Array.from(content).slice(0, 160).join('') };
        }),
        total,
        page: query.page,
        pageSize: query.pageSize,
        totalPages: Math.ceil(total / query.pageSize),
        hasMore,
        nextCursor: hasMore && last ? `${last.created_at}|${last.id}` : null,
      };
    });
  }
  async listFiles(userId: string, query: ListFilesDto) {
    const union = `(
      SELECT a.id AS file_id,a.message_id,'attachment' AS kind,a.name,a.mime_type,a.size,
        CASE WHEN a.preview IS NOT NULL THEN 1 ELSE 0 END AS has_preview,a.width,a.height,
        m.conversation_id,c.title AS conversation_title,m.content,m.created_at
      FROM message_attachments a
      JOIN messages m ON m.id=a.message_id
      JOIN conversations c ON c.id=m.conversation_id AND c.user_id=m.user_id
      WHERE m.user_id=? AND a.deleted_at IS NULL
      UNION ALL
      SELECT m.id AS file_id,m.id AS message_id,'image' AS kind,'图片' AS name,i.mime_type,i.size,
        1 AS has_preview,i.width,i.height,m.conversation_id,c.title AS conversation_title,
        m.content,m.created_at
      FROM message_images i
      JOIN messages m ON m.id=i.message_id
      JOIN conversations c ON c.id=m.conversation_id AND c.user_id=m.user_id
      WHERE m.user_id=?
    ) files`;
    const clauses = ['1=1'];
    const args: unknown[] = [userId, userId];
    if (query.kind) {
      clauses.push('kind=?');
      args.push(query.kind);
    }
    if (query.q) {
      const term = `%${query.q.replace(/[\\%_]/g, '\\$&')}%`;
      clauses.push(
        "(name LIKE ? ESCAPE '\\' OR conversation_title LIKE ? ESCAPE '\\' OR content LIKE ? ESCAPE '\\')",
      );
      args.push(term, term, term);
    }
    const where = clauses.join(' AND ');
    const countRows: { total: number }[] = await this.db.query(
      `SELECT COUNT(*) AS total FROM ${union} WHERE ${where}`,
      args,
    );
    const rows = await this.db.query(
      `SELECT file_id, message_id, kind, name, mime_type, size, has_preview, width, height,
        conversation_id, conversation_title, created_at
       FROM ${union} WHERE ${where}
       ORDER BY created_at DESC, file_id DESC LIMIT ? OFFSET ?`,
      [...args, query.pageSize, (query.page - 1) * query.pageSize],
    );
    const total = countRows[0]?.total ?? 0;
    return {
      items: rows.map((row: Record<string, unknown>) => ({
        id: row.file_id,
        messageId: row.message_id,
        kind: row.kind,
        name: row.name,
        mimeType: row.mime_type,
        size: row.size,
        hasPreview: Boolean(row.has_preview),
        width: row.width,
        height: row.height,
        conversationId: row.conversation_id,
        conversationTitle: row.conversation_title,
        createdAt: row.created_at,
      })),
      total,
      page: query.page,
      pageSize: query.pageSize,
      totalPages: Math.ceil(total / query.pageSize),
    };
  }
  async detail(userId: string, id: string) {
    const rows: MessageRow[] = await this.db.query(
      `SELECT messages.*, (SELECT c.title FROM conversations c WHERE c.id=messages.conversation_id AND c.user_id=messages.user_id) AS conversation_title, ${attachmentMetadataSQL} AS attachments_json, i.mime_type, i.width, i.height, i.size FROM messages LEFT JOIN message_images i ON i.message_id=messages.id WHERE messages.id = ? AND user_id = ?`,
      [id, userId],
    );
    if (!rows[0]) throw new NotFoundException('消息不存在');
    return serialize(rows[0]);
  }
  async createAttachments(
    userId: string,
    conversationId: string,
    files: Express.Multer.File[] | undefined,
    content: string,
    names: string | undefined,
    deviceId?: string | null,
    clientId?: string,
  ) {
    const attachments = await prepareAttachments(files, names);
    const text = content.trim() || '[附件] ' + attachments.map((f) => f.name).join('、');
    return this.create(
      userId,
      { title: Array.from(text).slice(0, 80).join(''), content: text, source: 'device', clientId },
      deviceId,
      conversationId,
      undefined,
      attachments,
    );
  }

  async attachment(userId: string, messageId: string, id: string, preview = false) {
    return this.db.transaction(async (m) => {
      const [row] = await m.query(
        `SELECT ${preview ? 'a.preview' : 'a.data'} AS data,a.name FROM message_attachments a JOIN messages m ON m.id=a.message_id WHERE m.id=? AND a.id=? AND m.user_id=? AND a.deleted_at IS NULL`,
        [messageId, id, userId],
      );
      if (!row?.data) throw new NotFoundException('文件不存在或已被自动清理');
      await m.query('UPDATE message_attachments SET last_accessed_at=? WHERE id=?', [
        Date.now(),
        id,
      ]);
      return row;
    });
  }

  async createImage(
    userId: string,
    conversationId: string,
    file: Express.Multer.File | undefined,
    content: string,
    deviceId?: string | null,
    clientId?: string,
  ) {
    if (!file?.buffer?.length) throw new BadRequestException('请选择图片');
    let image: ImageUpload;
    try {
      const input = sharp(file.buffer, { limitInputPixels: 24_000_000, failOn: 'warning' });
      const metadata = await input.metadata();
      if (!['jpeg', 'png', 'webp', 'gif'].includes(metadata.format ?? ''))
        throw new Error('Unsupported image');
      // Decode and re-encode the first frame; strip metadata and never serve active formats such as SVG.
      const output = await input
        .rotate()
        .webp({ quality: 90 })
        .toBuffer({ resolveWithObject: true });
      if (output.data.length > 8 * 1024 * 1024) throw new Error('Image too large');
      image = {
        data: output.data,
        mimeType: 'image/webp',
        width: output.info.width,
        height: output.info.height,
      };
    } catch {
      throw new BadRequestException(
        '图片无法解码或尺寸过大，请使用 JPEG、PNG、WebP 或 GIF（最多 2400 万像素）',
      );
    }
    const text = content.trim() || '[图片]';
    return this.create(
      userId,
      { title: Array.from(text).slice(0, 80).join(''), content: text, source: 'device', clientId },
      deviceId,
      conversationId,
      image,
    );
  }

  async image(userId: string, id: string) {
    return this.db.transaction(async (m) => {
      const [row] = await m.query(
        'SELECT i.data,i.mime_type FROM message_images i JOIN messages m ON m.id=i.message_id WHERE m.id=? AND m.user_id=?',
        [id, userId],
      );
      if (!row) throw new NotFoundException('图片不存在或已被自动清理');
      await m.query('UPDATE message_images SET last_accessed_at=? WHERE message_id=?', [
        Date.now(),
        id,
      ]);
      return row;
    });
  }

  async update(userId: string, id: string, dto: UpdateMessageDto) {
    const fields: string[] = [];
    const args: unknown[] = [];
    if (dto.annotation !== undefined) {
      fields.push('annotation = ?');
      args.push(dto.annotation);
    }
    if (dto.title !== undefined) {
      fields.push('title = ?');
      args.push(dto.title);
    }
    if (dto.content !== undefined) {
      fields.push('content = ?');
      args.push(dto.content);
    }
    if (dto.isRead !== undefined) {
      fields.push('is_read = ?');
      args.push(dto.isRead ? 1 : 0);
    }
    if (dto.isStarred !== undefined) {
      fields.push('is_starred = ?');
      args.push(dto.isStarred ? 1 : 0);
    }
    if (!fields.length) throw new BadRequestException('请至少填写一项内容');
    await this.detail(userId, id);
    await this.db.query(
      `UPDATE messages SET ${fields.join(', ')}, updated_at = ? WHERE id = ? AND user_id = ?`,
      [...args, new Date().toISOString(), id, userId],
    );
    return this.detail(userId, id);
  }
  async remove(userId: string, id: string) {
    await this.detail(userId, id);
    await this.db.query('DELETE FROM messages WHERE id = ? AND user_id = ?', [id, userId]);
  }
}
