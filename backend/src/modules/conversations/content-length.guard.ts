import {
  CanActivate,
  ExecutionContext,
  Injectable,
  PayloadTooLargeException,
  SetMetadata,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import type { Request, Response } from 'express';

const MAX_CONTENT_LENGTH_KEY = 'maxContentLength';
const DRAIN_LIMIT_BYTES = 64 * 1024 * 1024;
const DRAIN_TIMEOUT_MS = 2_000;

export const MaxContentLength = (bytes: number) => SetMetadata(MAX_CONTENT_LENGTH_KEY, bytes);

/**
 * Rejects oversized upload requests before Multer buffers multipart parts in memory.
 */
@Injectable()
export class ContentLengthGuard implements CanActivate {
  constructor(private readonly reflector: Reflector) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const limit = this.reflector.get<number | undefined>(
      MAX_CONTENT_LENGTH_KEY,
      context.getHandler(),
    );
    if (limit === undefined) return true;
    const http = context.switchToHttp();
    const request = http.getRequest<Request>();
    const response = http.getResponse<Response>();
    const raw = request.headers?.['content-length'];
    const header = Array.isArray(raw) ? raw[0] : raw;
    if (header !== undefined) {
      const length = Number(header);
      if (Number.isFinite(length) && length > limit) {
        await this.discardOversizedBody(request, response, length);
        throw new PayloadTooLargeException('上传内容超过大小限制');
      }
    }
    return true;
  }

  private discardOversizedBody(
    request: Request,
    response: Response,
    length: number,
  ): Promise<void> {
    if (length > DRAIN_LIMIT_BYTES || !request.readable || request.destroyed) {
      response.setHeader('Connection', 'close');
      request.resume();
      return Promise.resolve();
    }
    return new Promise((resolve) => {
      let settled = false;
      const timer = setTimeout(() => {
        response.setHeader('Connection', 'close');
        finish();
      }, DRAIN_TIMEOUT_MS);
      const finish = () => {
        if (settled) return;
        settled = true;
        clearTimeout(timer);
        request.off('end', finish);
        request.off('close', finish);
        request.off('error', finish);
        resolve();
      };
      request.once('end', finish);
      request.once('close', finish);
      request.once('error', finish);
      request.resume();
    });
  }
}
