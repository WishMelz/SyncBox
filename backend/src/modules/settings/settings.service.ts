import {
  BadRequestException,
  ConflictException,
  Injectable,
  Logger,
  OnModuleDestroy,
  OnModuleInit,
  UnauthorizedException,
} from '@nestjs/common';
import { createHash, randomBytes } from 'node:crypto';
import { DatabaseService } from '../../database/database.service';
import { AuthService } from '../auth/auth.service';
import { verifyPassword } from '../auth/password';
import { matchCounter, newSecret, openSecret, recoveryHash, sealSecret } from '../auth/totp';
import { CleanupDto, ResetDto, SecurityDto } from './settings.dto';
const digest = (token: string) => createHash('sha256').update(token).digest('hex');
@Injectable()
export class SettingsService implements OnModuleInit, OnModuleDestroy {
  private timer?: ReturnType<typeof setInterval>;
  private readonly logger = new Logger(SettingsService.name);
  constructor(
    private readonly db: DatabaseService,
    private readonly auth: AuthService,
  ) {}
  onModuleInit() {
    if (process.env.NODE_ENV === 'test') return;
    this.timer = setInterval(
      () => void this.cleanup().catch(() => this.logger.error('Automatic file cleanup failed')),
      10 * 60 * 1000,
    );
    this.timer.unref();
  }
  onModuleDestroy() {
    if (this.timer) clearInterval(this.timer);
  }
  async get(userId: string) {
    return this.db.transaction(async (m) => {
      const [user] = await m.query('SELECT totp_secret,recovery_hashes FROM users WHERE id=?', [
        userId,
      ]);
      if (!user) throw new UnauthorizedException();
      const [s] = await m.query('SELECT * FROM user_settings WHERE user_id=?', [userId]);
      const [files] = await m.query(
        `SELECT COUNT(*) count,COALESCE(SUM(size),0) bytes FROM (
        SELECT a.size FROM message_attachments a JOIN messages m ON m.id=a.message_id WHERE m.user_id=? AND a.deleted_at IS NULL
        UNION ALL SELECT i.size FROM message_images i JOIN messages m ON m.id=i.message_id WHERE m.user_id=?)`,
        [userId, userId],
      );
      return {
        cleanup: {
          enabled: !!s?.cleanup_enabled,
          idleDays: s?.idle_days ?? 30,
          lastRunAt: s?.last_cleanup_at ?? null,
          lastDeletedCount: s?.last_cleanup_count ?? 0,
        },
        twoFactorEnabled: !!user.totp_secret,
        recoveryCodesRemaining: JSON.parse(user.recovery_hashes ?? '[]').length,
        storage: { fileCount: files.count, bytes: files.bytes },
      };
    });
  }
  async backup(userId: string) {
    await this.get(userId);
    return this.db.createBackup();
  }
  async setCleanup(userId: string, dto: CleanupDto) {
    await this.db.query(
      `INSERT INTO user_settings(user_id,cleanup_enabled,idle_days) VALUES(?,?,?)
      ON CONFLICT(user_id) DO UPDATE SET cleanup_enabled=excluded.cleanup_enabled,idle_days=excluded.idle_days`,
      [userId, Number(dto.enabled), dto.idleDays],
    );
    return this.get(userId);
  }
  async cleanup(now = Date.now()) {
    const total = await this.db.transaction(async (m) => {
      const settings = await m.query('SELECT * FROM user_settings WHERE cleanup_enabled=1');
      let total = 0;
      for (const s of settings) {
        const cutoff = now - s.idle_days * 86400000;
        const attachments = await m.query(
          `SELECT a.id FROM message_attachments a JOIN messages m ON m.id=a.message_id WHERE m.user_id=? AND a.last_accessed_at<=? AND a.deleted_at IS NULL`,
          [s.user_id, cutoff],
        );
        const images = await m.query(
          `SELECT i.message_id FROM message_images i JOIN messages m ON m.id=i.message_id WHERE m.user_id=? AND i.last_accessed_at<=?`,
          [s.user_id, cutoff],
        );
        for (const a of attachments)
          await m.query(
            "UPDATE message_attachments SET data=X'',preview=NULL,deleted_at=? WHERE id=?",
            [now, a.id],
          );
        for (const i of images) {
          await m.query('UPDATE messages SET files_expired=1 WHERE id=?', [i.message_id]);
          await m.query('DELETE FROM message_images WHERE message_id=?', [i.message_id]);
        }
        const count = attachments.length + images.length;
        await m.query(
          'UPDATE user_settings SET last_cleanup_at=?,last_cleanup_count=? WHERE user_id=?',
          [now, count, s.user_id],
        );
        total += count;
      }
      return total;
    });
    if (total > 0) await this.compact();
    return total;
  }
  async beginTwoFactor(userId: string, token: string, dto: SecurityDto) {
    return this.db.transaction(async (m) => {
      const [u] = await m.query('SELECT * FROM users WHERE id=?', [userId]);
      if (!u || !(await verifyPassword(dto.password, u.password_hash)))
        throw new UnauthorizedException('密码错误，请重试');
      if (u.totp_secret) throw new ConflictException('两步认证已开启');
      const secret = newSecret();
      const pending = JSON.stringify({
        secret: await sealSecret(secret, dto.password),
        session: digest(token),
      });
      await m.query('UPDATE users SET totp_pending=?,totp_pending_until=? WHERE id=?', [
        pending,
        Date.now() + 10 * 60000,
        userId,
      ]);
      return {
        secret,
        otpauthUri: `otpauth://totp/${encodeURIComponent('SyncBox:' + u.username)}?secret=${secret}&issuer=SyncBox&algorithm=SHA1&digits=6&period=30`,
        expiresIn: 600,
      };
    });
  }
  async enableTwoFactor(userId: string, token: string, dto: SecurityDto) {
    return this.db.transaction(async (m) => {
      const [u] = await m.query('SELECT * FROM users WHERE id=?', [userId]);
      if (!u || !(await verifyPassword(dto.password, u.password_hash)))
        throw new UnauthorizedException('密码错误，请重试');
      if (u.totp_secret) throw new ConflictException('两步认证已开启');
      if (!u.totp_pending || u.totp_pending_until < Date.now())
        throw new BadRequestException('设置已过期，请重新开始');
      const pending = JSON.parse(u.totp_pending);
      if (pending.session !== digest(token))
        throw new BadRequestException('请在发起设置的设备上完成验证');
      const counter = matchCounter(
        await openSecret(pending.secret, dto.password),
        dto.code ?? '',
        -1,
      );
      if (counter === null) throw new BadRequestException('动态码不正确，请检查验证器及设备时间');
      const codes = Array.from({ length: 8 }, () =>
        randomBytes(10).toString('hex').match(/.{5}/g)!.join('-'),
      );
      await m.query(
        'UPDATE users SET totp_secret=?,totp_last_counter=?,recovery_hashes=?,totp_pending=NULL,totp_pending_until=NULL WHERE id=?',
        [pending.secret, counter, JSON.stringify(codes.map(recoveryHash)), userId],
      );
      await m.query('DELETE FROM sessions WHERE user_id=? AND token_hash<>?', [
        userId,
        digest(token),
      ]);
      return { recoveryCodes: codes };
    });
  }
  async disableTwoFactor(userId: string, token: string, dto: SecurityDto) {
    await this.db.transaction(async (m) => {
      await this.auth.verifySecurity(m, userId, dto.password, dto.code);
      await m.query(
        'UPDATE users SET totp_secret=NULL,totp_pending=NULL,totp_pending_until=NULL,recovery_hashes=NULL,totp_last_counter=-1 WHERE id=?',
        [userId],
      );
      await m.query('DELETE FROM sessions WHERE user_id=? AND token_hash<>?', [
        userId,
        digest(token),
      ]);
    });
    return this.get(userId);
  }
  async reset(userId: string, dto: ResetDto) {
    await this.db.transaction(async (m) => {
      await this.auth.verifySecurity(m, userId, dto.password, dto.code);
      // Foreign keys cascade to all live application data. External backups are untouched.
      await m.query('DELETE FROM users WHERE id=?', [userId]);
    });
    await this.compact();
  }
  private async compact() {
    // Reclaim SQLite pages after deleting BLOBs; failure must not undo successful deletion.
    try {
      await this.db.query('VACUUM');
      await this.db.query('PRAGMA wal_checkpoint(TRUNCATE)');
    } catch {
      this.logger.warn('Data deleted; database compaction deferred');
    }
  }
}
