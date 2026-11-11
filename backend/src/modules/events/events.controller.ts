import { Controller, Get, Req, Res } from '@nestjs/common';
import type { Request, Response } from 'express';
import { AuthService } from '../auth/auth.service';
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
      response.status(401).json({ message: 'Bearer token required' });
      return;
    }
    let user;
    try {
      user = await this.auth.authenticate(token);
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
    const heartbeat = setInterval(() => response.write(': heartbeat\n\n'), 20_000);
    const unsubscribe = this.events.subscribe(user.id, (event) => {
      response.write(`event: sync\ndata: ${JSON.stringify(event)}\n\n`);
    });
    const close = () => {
      clearInterval(heartbeat);
      unsubscribe();
    };
    request.on('close', close);
    response.on('close', close);
  }
}
