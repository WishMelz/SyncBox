import { Injectable } from '@nestjs/common';
import { EventEmitter } from 'node:events';

export type SyncEvent = {
  type: 'invalidate';
  scope: 'conversations' | 'messages' | 'favorites' | 'devices' | 'settings';
  conversationId?: string;
  messageId?: string;
  at: number;
};

@Injectable()
export class EventBus {
  private readonly emitter = new EventEmitter();

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
}
