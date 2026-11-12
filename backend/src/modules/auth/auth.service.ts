import type { EntityManager } from 'typeorm';
import { matchCounter, openSecret, recoveryHash } from './totp';
import { ConflictException, Injectable, UnauthorizedException } from '@nestjs/common';
import { DatabaseService } from '../../database/database.service';
import { createHash, randomBytes, randomUUID } from 'node:crypto';
import { LoginDto, SetupDto } from './auth.dto';
import { hashPassword, verifyPassword } from './password';

export interface CurrentUser {
  id: string;
  username: string;
  name: string;
  createdAt: string;
  deviceId?: string | null;
}
interface UserRow {
  id: string;
  username: string;
  name: string;
  created_at: string;
  password_hash: string;
  totp_secret?: string | null;
}
const SESSION_SECONDS = 7 * 24 * 60 * 60;
const digest = (token: string) => createHash('sha256').update(token).digest('hex');
const publicUser = (row: UserRow): CurrentUser => ({
  id: row.id,
  username: row.username,
  name: row.name,
  createdAt: row.created_at,
});

@Injectable()
export class AuthService {
  constructor(private readonly db: DatabaseService) {}

  async status() {
    const [row] = await this.db.query('SELECT COUNT(*) AS total FROM users');
    return { initialized: row.total > 0 };
  }
  async setup(dto: SetupDto) {
    if ((await this.status()).initialized)
      throw new ConflictException('初始化已完成，请使用已有账号登录');
    const passwordHash = await hashPassword(dto.password);
    const row: UserRow = {
      id: randomUUID(),
      username: dto.username,
      name: dto.username,
      created_at: new Date().toISOString(),
      password_hash: passwordHash,
    };
    const token = randomBytes(32).toString('hex');
    try {
      await this.db.transaction(async (manager) => {
        const [existing] = await manager.query('SELECT COUNT(*) AS total FROM users');
        if (existing.total > 0) throw new ConflictException('初始化已完成，请使用已有账号登录');
        await manager.query(
          'INSERT INTO users (id,email,name,password_hash,created_at,username) VALUES (?,?,?,?,?,?)',
          [row.id, row.username, row.name, row.password_hash, row.created_at, row.username],
        );
        await manager.query('INSERT INTO sessions (token_hash,user_id,expires_at) VALUES (?,?,?)', [
          digest(token),
          row.id,
          Date.now() + SESSION_SECONDS * 1000,
        ]);
      });
    } catch (error) {
      if (error instanceof Error && /UNIQUE constraint failed/.test(error.message)) {
        throw new ConflictException('初始化已完成，请使用已有账号登录');
      }
      throw error;
    }
    return {
      accessToken: token,
      tokenType: 'Bearer',
      expiresIn: SESSION_SECONDS,
      user: publicUser(row),
    };
  }

  async login(dto: LoginDto) {
    const rows: UserRow[] = await this.db.query(
      'SELECT * FROM users WHERE username = ? COLLATE NOCASE',
      [dto.username],
    );
    const row = rows[0];
    // Perform the same expensive password derivation for unknown accounts.
    const valid = await verifyPassword(
      dto.password,
      row?.password_hash ?? `${'0'.repeat(32)}:${'0'.repeat(128)}`,
    );
    if (!row || !valid) throw new UnauthorizedException('用户名或密码错误');
    // Complete the password step before asking for the second factor. No
    // session or login challenge is created until the verification code passes.
    if (row.totp_secret && !dto.code) {
      throw new UnauthorizedException({
        code: 'TWO_FACTOR_REQUIRED',
        message: '密码已验证，请输入验证器动态码或恢复码',
      });
    }
    const token = randomBytes(32).toString('hex');
    await this.db.transaction(async (manager) => {
      await this.verifySecurity(manager, row.id, dto.password, dto.code);
      await manager.query('DELETE FROM sessions WHERE expires_at <= ?', [Date.now()]);
      await manager.query('INSERT INTO sessions (token_hash,user_id,expires_at) VALUES (?,?,?)', [
        digest(token),
        row.id,
        Date.now() + SESSION_SECONDS * 1000,
      ]);
    });
    return {
      accessToken: token,
      tokenType: 'Bearer',
      expiresIn: SESSION_SECONDS,
      user: publicUser(row),
    };
  }

  async verifySecurity(manager: EntityManager, id: string, password: string, code?: string) {
    const [row] = await manager.query('SELECT * FROM users WHERE id=?', [id]);
    if (!row || !(await verifyPassword(password, row.password_hash)))
      throw new UnauthorizedException('密码错误，请重试');
    if (row.totp_secret) {
      if (!code)
        throw new UnauthorizedException({
          code: 'TWO_FACTOR_REQUIRED',
          message: '请输入验证器动态码或恢复码',
        });
      const counter = matchCounter(
        await openSecret(row.totp_secret, password),
        code,
        row.totp_last_counter,
      );
      if (counter !== null) {
        await manager.query('UPDATE users SET totp_last_counter=? WHERE id=?', [counter, id]);
      } else {
        const hashes: string[] = JSON.parse(row.recovery_hashes ?? '[]');
        const index = hashes.indexOf(recoveryHash(code));
        if (index < 0)
          throw new UnauthorizedException('动态码无效或已使用，请等待下一组动态码，或使用恢复码');
        hashes.splice(index, 1);
        await manager.query('UPDATE users SET recovery_hashes=? WHERE id=?', [
          JSON.stringify(hashes),
          id,
        ]);
      }
    }
    return row;
  }

  async authenticate(token: string): Promise<CurrentUser> {
    if (!/^[a-f0-9]{64}$/.test(token)) throw new UnauthorizedException('登录已失效，请重新登录');
    const rows: (UserRow & { device_id: string | null })[] = await this.db.query(
      `SELECT u.*, s.device_id FROM users u JOIN sessions s ON s.user_id = u.id WHERE s.token_hash = ? AND s.expires_at > ?`,
      [digest(token), Date.now()],
    );
    if (!rows[0]) throw new UnauthorizedException('登录已失效，请重新登录');
    if (rows[0].device_id)
      await this.db.query('UPDATE devices SET last_seen_at = ? WHERE id = ? AND user_id = ?', [
        new Date().toISOString(),
        rows[0].device_id,
        rows[0].id,
      ]);
    return { ...publicUser(rows[0]), deviceId: rows[0].device_id };
  }

  async logout(token: string) {
    await this.db.query('DELETE FROM sessions WHERE token_hash = ?', [digest(token)]);
  }
}
