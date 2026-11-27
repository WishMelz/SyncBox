import { Controller, Get, Req, Res } from '@nestjs/common';
import type { Request, Response } from 'express';
import { AuthService, tokenDigest } from '../auth/auth.service';
import { EventBus } from '../../events/events.service';

@Controller('events')
export class EventsController {
  constructor(
    private readonly auth: AuthService,
    private readonly events: EventBus,
  ) {}

  @Get()
  async stream(@Req() request: Request, @Res() response: Response) {
    const header = request.header('authorization');
    const token = /^Bearer ([a-f0-9]{64})$/i.exec(header ?? '')?.[1];
    if (!token || !/^[a-f0-9]{64}$/i.test(token)) {
      response.status(401).json({ message: '请先登录' });
      return;
    }
    let user;
    try {
      user = await this.auth.validateSession(token, true);
    } catch {
      response.status(401).json({ message: '登录已过期，请重新登录' });
      return;
    }
    response.status(200);
    response.setHeader('Content-Type', 'text/event-stream; charset=utf-8');
    response.setHeader('Cache-Control', 'no-cache, no-transform');
    response.setHeader('Connection', 'keep-alive');
    response.setHeader('X-Accel-Buffering', 'no');
    response.flushHeaders?.();
    response.write(`retry: 3000\n\n`);

    const configuredMs = Number(process.env.SSE_HEARTBEAT_MS ?? 20_000);
    const heartbeatMs =
      Number.isFinite(configuredMs) && configuredMs >= 20 ? Math.trunc(configuredMs) : 20_000;
    let closed = false;
    let ticks = 0;
    let checking = false;
    let cleanupRegistry: () => void = () => undefined;

    const unsubscribe = this.events.subscribe(user.id, (event) => {
      if (!closed && !response.writableEnded) {
        response.write(`event: sync\ndata: ${JSON.stringify(event)}\n\n`);
      }
    });

    const close = () => {
      if (closed) return;
      closed = true;
      clearInterval(heartbeat);
      unsubscribe();
      cleanupRegistry();
      if (!response.writableEnded) response.end();
    };

    const heartbeat = setInterval(() => {
      if (closed || response.writableEnded) {
        close();
        return;
      }
      ticks += 1;
      if (ticks % 3 === 0) {
        if (checking) return;
        checking = true;
        void this.auth
          .validateSession(token, true)
          .then(() => {
            if (!closed && !response.writableEnded) response.write(': heartbeat\n\n');
          })
          .catch(() => {
            close();
          })
          .finally(() => {
            checking = false;
          });
        return;
      }
      response.write(': heartbeat\n\n');
    }, heartbeatMs);
    heartbeat.unref?.();

    cleanupRegistry = this.events.registerStream({
      userId: user.id,
      tokenHash: tokenDigest(token),
      deviceId: user.deviceId,
      close,
    });

    request.on('close', close);
    response.on('close', close);
  }
}
