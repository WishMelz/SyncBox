import { Injectable } from '@nestjs/common';
import { EventEmitter } from 'node:events';

export type SyncEvent = {
  type: 'invalidate';
  scope: 'conversations' | 'messages' | 'favorites' | 'devices' | 'settings';
  conversationId?: string;
  messageId?: string;
  at: number;
};

export interface SyncStreamEntry {
  userId: string;
  tokenHash: string;
  deviceId?: string | null;
  close: () => void;
}

@Injectable()
export class EventBus {
  private readonly emitter = new EventEmitter();
  private readonly streams = new Set<SyncStreamEntry>();

  constructor() {
    this.emitter.setMaxListeners(0);
  }

  publish(userId: string, event: Omit<SyncEvent, 'at'>) {
    this.emitter.emit(userId, { ...event, at: Date.now() } satisfies SyncEvent);
  }

  subscribe(userId: string, listener: (event: SyncEvent) => void) {
    this.emitter.on(userId, listener);
    return () => this.emitter.off(userId, listener);
  }

  registerStream(entry: SyncStreamEntry) {
    this.streams.add(entry);
    return () => {
      this.streams.delete(entry);
    };
  }

  bindStreamDevice(tokenHash: string, deviceId: string) {
    for (const entry of this.streams) {
      if (entry.tokenHash === tokenHash) entry.deviceId = deviceId;
    }
  }

  revokeByTokenHash(tokenHash: string) {
    for (const entry of [...this.streams]) {
      if (entry.tokenHash === tokenHash) entry.close();
    }
  }

  revokeByDeviceId(userId: string, deviceId: string) {
    for (const entry of [...this.streams]) {
      if (entry.userId === userId && entry.deviceId === deviceId) entry.close();
    }
  }

  revokeOtherSessions(userId: string, keepTokenHash: string) {
    for (const entry of [...this.streams]) {
      if (entry.userId === userId && entry.tokenHash !== keepTokenHash) entry.close();
    }
  }

  revokeUser(userId: string) {
    for (const entry of [...this.streams]) {
      if (entry.userId === userId) entry.close();
    }
  }
}
