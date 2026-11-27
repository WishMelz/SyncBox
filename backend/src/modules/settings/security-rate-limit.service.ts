import { HttpException, HttpStatus, Injectable } from '@nestjs/common';

const FAILURE_WINDOW_MS = 5 * 60 * 1000;
const MAX_FAILURES_PER_DIMENSION = 5;

/**
 * Limits repeated password / 2FA verification failures across both account ID
 * and client IP dimensions so a valid session token cannot brute-force secrets.
 */
@Injectable()
export class SecurityRateLimitService {
  private readonly failures = new Map<string, number[]>();

  assertAllowed(userId: string, ip: string, now = Date.now()) {
    for (const key of this.keys(userId, ip)) {
      const recent = this.prune(key, now);
      if (recent.length >= MAX_FAILURES_PER_DIMENSION) {
        throw new HttpException('验证失败次数过多，请稍后再试', HttpStatus.TOO_MANY_REQUESTS);
      }
    }
  }

  recordFailure(userId: string, ip: string, now = Date.now()) {
    for (const key of this.keys(userId, ip)) {
      const recent = this.prune(key, now);
      recent.push(now);
      this.failures.set(key, recent);
    }
  }

  reset(userId: string, ip: string) {
    for (const key of this.keys(userId, ip)) {
      this.failures.delete(key);
    }
  }

  private keys(userId: string, ip: string) {
    return [`user:${userId}`, `ip:${ip || 'unknown'}`];
  }

  private prune(key: string, now: number) {
    const cutoff = now - FAILURE_WINDOW_MS;
    const recent = (this.failures.get(key) ?? []).filter((ts) => ts > cutoff);
    if (recent.length) this.failures.set(key, recent);
    else this.failures.delete(key);
    return recent;
  }
}
