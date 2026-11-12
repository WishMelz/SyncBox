import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { createHash, randomUUID } from 'node:crypto';
import { DatabaseService } from '../../database/database.service';
import { RegisterDeviceDto } from './devices.dto';

const columns = `id,name,platform,created_at AS createdAt,last_seen_at AS lastSeenAt,
  CASE WHEN browser_fingerprint_hash IS NOT NULL OR (installation_hash IS NOT NULL AND fingerprint_hash IS NOT NULL) THEN 1 ELSE 0 END AS fingerprintBound,
  CASE WHEN browser_fingerprint_hash IS NOT NULL THEN 'fingerprint' WHEN installation_hash IS NOT NULL THEN 'installation' ELSE 'legacy' END AS identityMode`;
const serialize = (row: any) => ({
  ...row,
  fingerprintBound: !!row.fingerprintBound,
  ...(row.online === undefined ? {} : { online: !!row.online }),
});

@Injectable()
export class DevicesService {
  constructor(private readonly db: DatabaseService) {}
  async register(userId: string, token: string, dto: RegisterDeviceDto) {
    const browserIdentity = dto.identityMode === 'fingerprint';
    if (browserIdentity && (dto.platform !== 'web' || !dto.fingerprint?.trim()))
      throw new BadRequestException('浏览器指纹模式仅用于 Web，且必须提交指纹');
    if (!browserIdentity && dto.fingerprint !== undefined && !dto.installationId)
      throw new BadRequestException('指纹必须与安装标识一起提交');
    const installationHash =
      !browserIdentity && dto.installationId
        ? createHash('sha256').update(dto.installationId.toLowerCase()).digest('hex')
        : null;
    const fingerprintHash = dto.fingerprint
      ? createHash('sha256').update(dto.fingerprint).digest('hex')
      : null;
    const now = new Date().toISOString();
    return this.db.transaction(async (manager) => {
      let existing = browserIdentity
        ? (
            await manager.query(
              'SELECT * FROM devices WHERE user_id=? AND platform=? AND browser_fingerprint_hash=?',
              [userId, dto.platform, fingerprintHash],
            )
          )[0]
        : installationHash
          ? (
              await manager.query(
                'SELECT * FROM devices WHERE user_id=? AND platform=? AND installation_hash=?',
                [userId, dto.platform, installationHash],
              )
            )[0]
          : undefined;
      if (!existing && dto.id) {
        [existing] = await manager.query('SELECT * FROM devices WHERE id=? AND user_id=?', [
          dto.id,
          userId,
        ]);
        if (!existing) throw new NotFoundException('设备不存在');
        if (
          existing.platform !== dto.platform ||
          (existing.browser_fingerprint_hash &&
            existing.browser_fingerprint_hash !== (browserIdentity ? fingerprintHash : null))
        )
          throw new ConflictException('此设备 ID 已绑定其他浏览器指纹');
        if (
          !browserIdentity &&
          existing.installation_hash &&
          ((installationHash && existing.installation_hash !== installationHash) ||
            existing.platform !== dto.platform)
        )
          throw new ConflictException('此设备 ID 已绑定其他客户端');
      }
      if (!browserIdentity && existing?.browser_fingerprint_hash)
        throw new ConflictException('此设备已使用浏览器指纹绑定，请更新客户端');
      const id = existing?.id ?? randomUUID();
      if (existing) {
        await manager.query(
          'UPDATE devices SET name=?,platform=?,last_seen_at=?,installation_hash=COALESCE(?,installation_hash),fingerprint_hash=COALESCE(?,fingerprint_hash),browser_fingerprint_hash=COALESCE(?,browser_fingerprint_hash) WHERE id=? AND user_id=?',
          [
            browserIdentity || installationHash ? existing.name : dto.name,
            dto.platform,
            now,
            installationHash,
            fingerprintHash,
            browserIdentity ? fingerprintHash : null,
            id,
            userId,
          ],
        );
      } else {
        await manager.query(
          'INSERT INTO devices (id,user_id,name,platform,created_at,last_seen_at,installation_hash,fingerprint_hash,browser_fingerprint_hash) VALUES (?,?,?,?,?,?,?,?,?)',
          [
            id,
            userId,
            dto.name,
            dto.platform,
            now,
            now,
            installationHash,
            fingerprintHash,
            browserIdentity ? fingerprintHash : null,
          ],
        );
      }
      await manager.query('UPDATE sessions SET device_id=? WHERE token_hash=? AND user_id=?', [
        id,
        createHash('sha256').update(token).digest('hex'),
        userId,
      ]);
      const [device] = await manager.query(`SELECT ${columns} FROM devices WHERE id=?`, [id]);
      return serialize(device);
    });
  }
  async list(userId: string) {
    const onlineSince = new Date(Date.now() - 90_000).toISOString();
    const rows = await this.db.query(
      `SELECT ${columns},CASE WHEN last_seen_at>=? THEN 1 ELSE 0 END AS online
       FROM devices WHERE user_id=? ORDER BY last_seen_at DESC,id DESC`,
      [onlineSince, userId],
    );
    return rows.map(serialize);
  }
  async heartbeat(userId: string, deviceId?: string | null) {
    if (!deviceId) return;
    await this.db.query('UPDATE devices SET last_seen_at=? WHERE id=? AND user_id=?', [
      new Date().toISOString(),
      deviceId,
      userId,
    ]);
  }
  async rename(userId: string, id: string, name: string) {
    const rows = await this.db.query(
      `UPDATE devices SET name=?,last_seen_at=? WHERE id=? AND user_id=? RETURNING ${columns}`,
      [name, new Date().toISOString(), id, userId],
    );
    if (!rows[0]) throw new NotFoundException('设备不存在');
    return serialize(rows[0]);
  }
  async remove(userId: string, id: string) {
    await this.db.transaction(async (manager) => {
      const rows = await manager.query('SELECT id FROM devices WHERE id = ? AND user_id = ?', [
        id,
        userId,
      ]);
      if (!rows[0]) throw new NotFoundException('设备不存在');
      await manager.query('DELETE FROM sessions WHERE device_id = ? AND user_id = ?', [id, userId]);
      await manager.query('DELETE FROM devices WHERE id = ? AND user_id = ?', [id, userId]);
    });
  }
}
