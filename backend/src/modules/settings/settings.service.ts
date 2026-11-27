import {
  BadRequestException,
  ConflictException,
  Injectable,
  Logger,
  OnModuleDestroy,
  OnModuleInit,
  UnauthorizedException,
} from '@nestjs/common';
import { randomBytes } from 'node:crypto';
import { DatabaseService } from '../../database/database.service';
import { AuthService, tokenDigest } from '../auth/auth.service';
import { verifyPassword } from '../auth/password';
import { matchCounter, newSecret, openSecret, recoveryHash, sealSecret } from '../auth/totp';
import { CleanupDto, ResetDto, SecurityDto } from './settings.dto';
import { EventBus } from '../../events/events.service';
import { PresenceTracker } from '../auth/presence.tracker';
import { SecurityRateLimitService } from './security-rate-limit.service';

const digest = tokenDigest;

@Injectable()
export class SettingsService implements OnModuleInit, OnModuleDestroy {
  private timer?: ReturnType<typeof setInterval>;
  private readonly logger = new Logger(SettingsService.name);

  constructor(
    private readonly db: DatabaseService,
    private readonly auth: AuthService,
    private readonly events: EventBus,
    private readonly presence: PresenceTracker,
    private readonly rateLimit: SecurityRateLimitService,
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
      if (!user) throw new UnauthorizedException('请先登录');
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
    const affectedByUser = new Map<string, Set<string>>();
    const total = await this.db.transaction(async (m) => {
      const settings = await m.query('SELECT * FROM user_settings WHERE cleanup_enabled=1');
      let total = 0;
      for (const s of settings) {
        const cutoff = now - s.idle_days * 86400000;
        const attachments: { id: string; conversation_id: string }[] = await m.query(
          `SELECT a.id, m.conversation_id FROM message_attachments a JOIN messages m ON m.id=a.message_id WHERE m.user_id=? AND a.last_accessed_at<=? AND a.deleted_at IS NULL`,
          [s.user_id, cutoff],
        );
        const images: { message_id: string; conversation_id: string }[] = await m.query(
          `SELECT i.message_id, m.conversation_id FROM message_images i JOIN messages m ON m.id=i.message_id WHERE m.user_id=? AND i.last_accessed_at<=?`,
          [s.user_id, cutoff],
        );
        const conversationIds = new Set<string>();
        for (const a of attachments) {
          conversationIds.add(a.conversation_id);
          await m.query(
            "UPDATE message_attachments SET data=X'',preview=NULL,deleted_at=? WHERE id=?",
            [now, a.id],
          );
        }
        for (const i of images) {
          conversationIds.add(i.conversation_id);
          await m.query('UPDATE messages SET files_expired=1 WHERE id=?', [i.message_id]);
          await m.query('DELETE FROM message_images WHERE message_id=?', [i.message_id]);
        }
        const count = attachments.length + images.length;
        await m.query(
          'UPDATE user_settings SET last_cleanup_at=?,last_cleanup_count=? WHERE user_id=?',
          [now, count, s.user_id],
        );
        if (count > 0) {
          affectedByUser.set(s.user_id, conversationIds);
        }
        total += count;
      }
      return total;
    });
    for (const [userId, conversationIds] of affectedByUser) {
      this.events.publish(userId, { type: 'invalidate', scope: 'settings' });
      this.events.publish(userId, { type: 'invalidate', scope: 'favorites' });
      for (const conversationId of conversationIds) {
        this.events.publish(userId, { type: 'invalidate', scope: 'messages', conversationId });
        this.events.publish(userId, { type: 'invalidate', scope: 'conversations', conversationId });
      }
    }
    if (total > 0) await this.compact(false);
    return total;
  }

  private async runWithSecurityRateLimit<T>(
    userId: string,
    ip: string,
    work: () => Promise<T>,
  ): Promise<T> {
    this.rateLimit.assertAllowed(userId, ip);
    try {
      const result = await work();
      this.rateLimit.reset(userId, ip);
      return result;
    } catch (error) {
      if (
        error instanceof UnauthorizedException ||
        (error instanceof BadRequestException && error.message.includes('动态码'))
      ) {
        this.rateLimit.recordFailure(userId, ip);
      }
      throw error;
    }
  }

  async beginTwoFactor(userId: string, token: string, dto: SecurityDto, ip = 'unknown') {
    return this.runWithSecurityRateLimit(userId, ip, () =>
      this.db.transaction(async (m) => {
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
      }),
    );
  }

  async enableTwoFactor(userId: string, token: string, dto: SecurityDto, ip = 'unknown') {
    const keepHash = digest(token);
    const result = await this.runWithSecurityRateLimit(userId, ip, () =>
      this.db.transaction(async (m) => {
        const [u] = await m.query('SELECT * FROM users WHERE id=?', [userId]);
        if (!u || !(await verifyPassword(dto.password, u.password_hash)))
          throw new UnauthorizedException('密码错误，请重试');
        if (u.totp_secret) throw new ConflictException('两步认证已开启');
        if (!u.totp_pending || u.totp_pending_until < Date.now())
          throw new BadRequestException('设置已过期，请重新开始');
        const pending = JSON.parse(u.totp_pending);
        if (pending.session !== keepHash)
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
        await m.query('DELETE FROM sessions WHERE user_id=? AND token_hash<>?', [userId, keepHash]);
        return { recoveryCodes: codes };
      }),
    );
    this.events.revokeOtherSessions(userId, keepHash);
    return result;
  }

  async disableTwoFactor(userId: string, token: string, dto: SecurityDto, ip = 'unknown') {
    const keepHash = digest(token);
    await this.runWithSecurityRateLimit(userId, ip, () =>
      this.db.transaction(async (m) => {
        await this.auth.verifySecurity(m, userId, dto.password, dto.code);
        await m.query(
          'UPDATE users SET totp_secret=NULL,totp_pending=NULL,totp_pending_until=NULL,recovery_hashes=NULL,totp_last_counter=-1 WHERE id=?',
          [userId],
        );
        await m.query('DELETE FROM sessions WHERE user_id=? AND token_hash<>?', [userId, keepHash]);
      }),
    );
    this.events.revokeOtherSessions(userId, keepHash);
    return this.get(userId);
  }

  async reset(userId: string, dto: ResetDto, ip = 'unknown') {
    await this.runWithSecurityRateLimit(userId, ip, () =>
      this.db.transaction(async (m) => {
        await this.auth.verifySecurity(m, userId, dto.password, dto.code);
        // Foreign keys cascade to all live application data. External backups are untouched.
        await m.query('DELETE FROM users WHERE id=?', [userId]);
      }),
    );
    this.events.revokeUser(userId);
    this.presence.clear();
    await this.compact(true);
  }

  private async compact(force = false) {
    // Reclaim SQLite pages after deleting BLOBs; failure must not undo successful deletion.
    try {
      let shouldVacuum = force;
      if (!shouldVacuum) {
        const [freeRow] = await this.db.query('PRAGMA freelist_count');
        const [pageRow] = await this.db.query('PRAGMA page_count');
        const [sizeRow] = await this.db.query('PRAGMA page_size');
        const freelistCount = Number(freeRow?.freelist_count ?? 0);
        const pageCount = Number(pageRow?.page_count ?? 0);
        const pageSize = Number(sizeRow?.page_size ?? 4096);
        const reclaimableBytes = freelistCount * pageSize;
        const ratio = pageCount > 0 ? freelistCount / pageCount : 0;
        shouldVacuum =
          reclaimableBytes >= 32 * 1024 * 1024 ||
          (reclaimableBytes >= 8 * 1024 * 1024 && ratio >= 0.2);
      }
      if (shouldVacuum) {
        await this.db.query('VACUUM');
        await this.db.query('PRAGMA wal_checkpoint(TRUNCATE)');
      } else {
        await this.db.query('PRAGMA wal_checkpoint(PASSIVE)');
      }
    } catch {
      this.logger.warn('Data deleted; database compaction deferred');
    }
  }
}
