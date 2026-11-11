import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  Param,
  ParseUUIDPipe,
  Post,
  Patch,
  Req,
  UseGuards,
} from '@nestjs/common';
import { AuthGuard, User, type AuthRequest } from '../auth/auth.guard';
import type { CurrentUser } from '../auth/auth.service';
import { DevicesService } from './devices.service';
import { RegisterDeviceDto } from './devices.dto';
import { IsString, Length } from 'class-validator';
import { Transform } from 'class-transformer';
import { EventBus } from '../../events/events.service';
class RenameDeviceDto {
  @Transform(({ value }) => (typeof value === 'string' ? value.trim() : value))
  @IsString()
  @Length(1, 80)
  name!: string;
}
@Controller('devices')
@UseGuards(AuthGuard)
export class DevicesController {
  constructor(private readonly devices: DevicesService, private readonly events: EventBus) {}
  @Post() async register(
    @User() user: CurrentUser,
    @Req() request: AuthRequest,
    @Body() dto: RegisterDeviceDto,
  ) {
    const result = await this.devices.register(user.id, request.token, dto);
    this.events.publish(user.id, { type: 'invalidate', scope: 'devices' });
    return result;
  }
  @Get() list(@User() user: CurrentUser) {
    return this.devices.list(user.id);
  }
  @Post('heartbeat') @HttpCode(204) async heartbeat(@User() user: CurrentUser) {
    await this.devices.heartbeat(user.id, user.deviceId);
  }
  @Patch(':id') async rename(
    @User() user: CurrentUser,
    @Param('id', new ParseUUIDPipe()) id: string,
    @Body() dto: RenameDeviceDto,
  ) {
    const result = await this.devices.rename(user.id, id, dto.name);
    this.events.publish(user.id, { type: 'invalidate', scope: 'devices' });
    return result;
  }
  @Delete(':id') @HttpCode(204) async remove(
    @User() user: CurrentUser,
    @Param('id', new ParseUUIDPipe()) id: string,
  ) {
    await this.devices.remove(user.id, id);
    this.events.publish(user.id, { type: 'invalidate', scope: 'devices' });
  }
}
