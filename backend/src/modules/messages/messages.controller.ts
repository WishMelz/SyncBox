import { StreamableFile } from '@nestjs/common';
import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import { AuthGuard, User } from '../auth/auth.guard';
import type { CurrentUser } from '../auth/auth.service';
import { MessagesService } from './messages.service';
import { CreateMessageDto, ListFilesDto, ListMessagesDto, UpdateMessageDto } from './messages.dto';
import { EventBus } from '../../events/events.service';

@Controller('messages')
@UseGuards(AuthGuard)
export class MessagesController {
  constructor(private readonly messages: MessagesService, private readonly events: EventBus) {}
  @Post() async create(@User() user: CurrentUser, @Body() dto: CreateMessageDto) {
    const result = await this.messages.create(user.id, dto, user.deviceId);
    this.events.publish(user.id, { type: 'invalidate', scope: 'messages', conversationId: result.conversationId });
    this.events.publish(user.id, { type: 'invalidate', scope: 'conversations', conversationId: result.conversationId });
    return result;
  }
  @Get() list(@User() user: CurrentUser, @Query() query: ListMessagesDto) {
    return this.messages.list(user.id, query);
  }
  @Get('files') files(@User() user: CurrentUser, @Query() query: ListFilesDto) {
    return this.messages.listFiles(user.id, query);
  }
  @Get('starred') starred(@User() user: CurrentUser, @Query() query: ListMessagesDto) {
    return this.messages.list(user.id, { ...query, isStarred: 'true' }, undefined, true);
  }
  @Get(':id/attachments/:attachmentId')
  async downloadAttachment(
    @User() user: CurrentUser,
    @Param('id', new ParseUUIDPipe()) id: string,
    @Param('attachmentId', new ParseUUIDPipe()) attachmentId: string,
  ) {
    const file = await this.messages.attachment(user.id, id, attachmentId);
    const name = encodeURIComponent(file.name).replace(
      /['()*]/g,
      (c) => '%' + c.charCodeAt(0).toString(16).toUpperCase(),
    );
    return new StreamableFile(file.data, {
      type: 'application/octet-stream',
      // Keep an ASCII fallback for clients that ignore filename* while
      // preserving the stored UTF-8 name for modern clients.
      disposition: `attachment; filename="download"; filename*=UTF-8''${name}`,
    });
  }
  @Get(':id/attachments/:attachmentId/preview')
  async previewAttachment(
    @User() user: CurrentUser,
    @Param('id', new ParseUUIDPipe()) id: string,
    @Param('attachmentId', new ParseUUIDPipe()) attachmentId: string,
  ) {
    const file = await this.messages.attachment(user.id, id, attachmentId, true);
    return new StreamableFile(file.data, {
      type: 'image/webp',
      disposition: 'inline; filename="preview.webp"',
    });
  }
  @Get(':id/image')
  async image(@User() user: CurrentUser, @Param('id', new ParseUUIDPipe()) id: string) {
    const image = await this.messages.image(user.id, id);
    return new StreamableFile(image.data, {
      type: image.mime_type,
      disposition: 'inline; filename="image.webp"',
    });
  }

  @Get(':id') detail(@User() user: CurrentUser, @Param('id', new ParseUUIDPipe()) id: string) {
    return this.messages.detail(user.id, id);
  }
  @Patch(':id') async update(
    @User() user: CurrentUser,
    @Param('id', new ParseUUIDPipe()) id: string,
    @Body() dto: UpdateMessageDto,
  ) {
    const result = await this.messages.update(user.id, id, dto);
    this.events.publish(user.id, { type: 'invalidate', scope: dto.isStarred !== undefined ? 'favorites' : 'messages', messageId: id });
    if (dto.isStarred !== undefined) this.events.publish(user.id, { type: 'invalidate', scope: 'messages', messageId: id });
    if (dto.isRead !== undefined) this.events.publish(user.id, { type: 'invalidate', scope: 'conversations', conversationId: result.conversationId });
    return result;
  }
  @Delete(':id') @HttpCode(204) async remove(
    @User() user: CurrentUser,
    @Param('id', new ParseUUIDPipe()) id: string,
  ) {
    await this.messages.remove(user.id, id);
    this.events.publish(user.id, { type: 'invalidate', scope: 'messages', messageId: id });
    this.events.publish(user.id, { type: 'invalidate', scope: 'favorites', messageId: id });
  }
}
