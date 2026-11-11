import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  Patch,
  Post,
  Req,
  UseGuards,
  StreamableFile,
  Res,
} from '@nestjs/common';
import type { Response } from 'express';
import { createReadStream, unlink } from 'node:fs';
import { Throttle } from '@nestjs/throttler';
import { AuthGuard, User, type AuthRequest } from '../auth/auth.guard';
import type { CurrentUser } from '../auth/auth.service';
import { CleanupDto, ResetDto, SecurityDto } from './settings.dto';
import { SettingsService } from './settings.service';
import { EventBus } from '../../events/events.service';
@Controller('settings')
@UseGuards(AuthGuard)
export class SettingsController {
  constructor(private readonly settings: SettingsService, private readonly events: EventBus) {}
  @Get() get(@User() u: CurrentUser) {
    return this.settings.get(u.id);
  }
  @Get('backup')
  async backup(@User() u: CurrentUser, @Res({ passthrough: true }) response: Response) {
    const file = await this.settings.backup(u.id);
    response.setHeader('Cache-Control', 'no-store');
    response.setHeader('Content-Disposition', `attachment; filename="${file.name}"`);
    response.setHeader('X-SyncBox-Backup-SHA256', file.sha256);
    response.setHeader('X-SyncBox-Backup-Size', String(file.size));
    response.setHeader('X-SyncBox-Backup-Created-At', file.createdAt);
    response.setHeader(
      'Access-Control-Expose-Headers',
      'Content-Disposition, X-SyncBox-Backup-SHA256, X-SyncBox-Backup-Size, X-SyncBox-Backup-Created-At',
    );
    const stream = createReadStream(file.path);
    stream.once('close', () => unlink(file.path, () => undefined));
    return new StreamableFile(stream, { type: 'application/x-sqlite3' });
  }
  @Patch('cleanup') async cleanup(@User() u: CurrentUser, @Body() dto: CleanupDto) {
    const result = await this.settings.setCleanup(u.id, dto);
    this.events.publish(u.id, { type: 'invalidate', scope: 'settings' });
    return result;
  }
  @Post('two-factor/setup')
  @Throttle({ default: { limit: 5, ttl: 60000 } })
  begin(@User() u: CurrentUser, @Req() req: AuthRequest, @Body() dto: SecurityDto) {
    return this.settings.beginTwoFactor(u.id, req.token, dto);
  }
  @Post('two-factor/enable')
  @Throttle({ default: { limit: 5, ttl: 60000 } })
  async enable(@User() u: CurrentUser, @Req() req: AuthRequest, @Body() dto: SecurityDto) {
    const result = await this.settings.enableTwoFactor(u.id, req.token, dto);
    this.events.publish(u.id, { type: 'invalidate', scope: 'settings' });
    return result;
  }
  @Post('two-factor/disable')
  @Throttle({ default: { limit: 5, ttl: 60000 } })
  async disable(@User() u: CurrentUser, @Req() req: AuthRequest, @Body() dto: SecurityDto) {
    const result = await this.settings.disableTwoFactor(u.id, req.token, dto);
    this.events.publish(u.id, { type: 'invalidate', scope: 'settings' });
    return result;
  }
  @Delete('data')
  @HttpCode(204)
  @Throttle({ default: { limit: 5, ttl: 60000 } })
  async reset(@User() u: CurrentUser, @Body() dto: ResetDto) {
    const result = await this.settings.reset(u.id, dto);
    this.events.publish(u.id, { type: 'invalidate', scope: 'settings' });
    return result;
  }
}
