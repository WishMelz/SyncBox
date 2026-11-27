import { Injectable } from '@nestjs/common';
import { DatabaseService } from '../../database/database.service';

const PRESENCE_THROTTLE_MS = 30_000;
const MAX_TRACKED_DEVICES = 10_000;

/**
 * Coalesces frequent device `last_seen_at` writes in memory so bursts of
 * authenticated requests and heartbeats do not queue redundant SQLite writes.
 */
@Injectable()
export class PresenceTracker {
  private readonly lastWritten = new Map<string, number>();

  async touch(
    userId: string,
    deviceId: string | null | undefined,
    db: DatabaseService,
    now = Date.now(),
  ): Promise<boolean> {
    if (!deviceId) return false;
    const previous = this.lastWritten.get(deviceId);
    if (previous !== undefined && now - previous < PRESENCE_THROTTLE_MS) {
      return false;
    }
    this.markUpdated(deviceId, now);
    try {
      await db.query('UPDATE devices SET last_seen_at = ? WHERE id = ? AND user_id = ?', [
        new Date(now).toISOString(),
        deviceId,
        userId,
      ]);
      return true;
    } catch (error) {
      this.lastWritten.delete(deviceId);
      throw error;
    }
  }

  markUpdated(deviceId: string, now = Date.now()) {
    if (this.lastWritten.size >= MAX_TRACKED_DEVICES && !this.lastWritten.has(deviceId)) {
      const oldest = this.lastWritten.keys().next().value;
      if (oldest !== undefined) this.lastWritten.delete(oldest);
    }
    this.lastWritten.set(deviceId, now);
  }

  evict(deviceId: string) {
    this.lastWritten.delete(deviceId);
  }

  clear() {
    this.lastWritten.clear();
  }
}
