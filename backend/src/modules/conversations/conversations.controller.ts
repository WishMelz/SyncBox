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
  UseInterceptors,
  UploadedFile,
  UploadedFiles,
} from '@nestjs/common';
import { AuthGuard, User } from '../auth/auth.guard';
import type { CurrentUser } from '../auth/auth.service';
import { MessagesService } from '../messages/messages.service';
import { ListMessagesDto } from '../messages/messages.dto';
import { ConversationsService } from './conversations.service';
import { FileInterceptor, FilesInterceptor } from '@nestjs/platform-express';
import { Throttle } from '@nestjs/throttler';
import { EventBus } from '../../events/events.service';
import {
  ConversationDto,
  SendMessageDto,
  SendImageDto,
  SendAttachmentsDto,
  UpdateConversationDto,
} from './conversations.dto';
@Controller('conversations')
@UseGuards(AuthGuard)
export class ConversationsController {
  constructor(
    private readonly conversations: ConversationsService,
    private readonly messages: MessagesService,
    private readonly events: EventBus,
  ) {}
  @Post() async create(@User() u: CurrentUser, @Body() dto: ConversationDto) {
    const result = await this.conversations.create(u.id, dto.title);
    this.events.publish(u.id, { type: 'invalidate', scope: 'conversations', conversationId: result.id });
    return result;
  }
  @Get() list(@User() u: CurrentUser, @Query() q: ListMessagesDto) {
    return this.conversations.list(u.id, q.q ?? '', q.page, q.pageSize);
  }
  @Get(':id') detail(@User() u: CurrentUser, @Param('id', new ParseUUIDPipe()) id: string) {
    return this.conversations.detail(u.id, id);
  }
  @Patch(':id') async rename(
    @User() u: CurrentUser,
    @Param('id', new ParseUUIDPipe()) id: string,
    @Body() dto: UpdateConversationDto,
  ) {
    const result = await this.conversations.update(u.id, id, dto);
    this.events.publish(u.id, { type: 'invalidate', scope: 'conversations', conversationId: id });
    return result;
  }
  @Delete(':id') @HttpCode(204) async remove(
    @User() u: CurrentUser,
    @Param('id', new ParseUUIDPipe()) id: string,
  ) {
    await this.conversations.remove(u.id, id);
    this.events.publish(u.id, { type: 'invalidate', scope: 'conversations', conversationId: id });
  }
  @Get(':id/messages') async history(
    @User() u: CurrentUser,
    @Param('id', new ParseUUIDPipe()) id: string,
    @Query() q: ListMessagesDto,
  ) {
    await this.conversations.detail(u.id, id);
    return this.messages.list(u.id, q, id);
  }
  @Patch(':id/read') @HttpCode(204) async markRead(
    @User() u: CurrentUser,
    @Param('id', new ParseUUIDPipe()) id: string,
  ) {
    await this.conversations.markRead(u.id, id);
    this.events.publish(u.id, { type: 'invalidate', scope: 'conversations', conversationId: id });
  }
  @Post(':id/attachments')
  @Throttle({ default: { limit: 20, ttl: 60000 } })
  @UseInterceptors(
    FilesInterceptor('files', 5, {
      limits: { fileSize: 20 * 1024 * 1024, files: 5, fields: 3, fieldSize: 200000, parts: 8 },
    }),
  )
  async sendAttachments(
    @User() u: CurrentUser,
    @Param('id', new ParseUUIDPipe()) id: string,
    @UploadedFiles() files: Express.Multer.File[] | undefined,
    @Body() dto: SendAttachmentsDto,
  ) {
    await this.conversations.detail(u.id, id);
    const result = await this.messages.createAttachments(
      u.id,
      id,
      files,
      dto.content ?? '',
      dto.names,
      u.deviceId,
      dto.clientId,
    );
    this.events.publish(u.id, { type: 'invalidate', scope: 'messages', conversationId: id });
    this.events.publish(u.id, { type: 'invalidate', scope: 'conversations', conversationId: id });
    return result;
  }
  @Post(':id/images')
  @Throttle({ default: { limit: 20, ttl: 60000 } })
  @UseInterceptors(
    FileInterceptor('image', {
      limits: { fileSize: 8 * 1024 * 1024, files: 1, fields: 2, fieldSize: 200000 },
    }),
  )
  async sendImage(
    @User() u: CurrentUser,
    @Param('id', new ParseUUIDPipe()) id: string,
    @UploadedFile() file: Express.Multer.File | undefined,
    @Body() dto: SendImageDto,
  ) {
    await this.conversations.detail(u.id, id);
    const result = await this.messages.createImage(u.id, id, file, dto.content ?? '', u.deviceId, dto.clientId);
    this.events.publish(u.id, { type: 'invalidate', scope: 'messages', conversationId: id });
    this.events.publish(u.id, { type: 'invalidate', scope: 'conversations', conversationId: id });
    return result;
  }
  @Post(':id/messages') async send(
    @User() u: CurrentUser,
    @Param('id', new ParseUUIDPipe()) id: string,
    @Body() dto: SendMessageDto,
  ) {
    await this.conversations.detail(u.id, id);
    const result = await this.messages.create(
      u.id,
      {
        title: Array.from(dto.content).slice(0, 80).join(''),
        content: dto.content,
        source: 'device',
        clientId: dto.clientId,
      },
      u.deviceId,
      id,
    );
    this.events.publish(u.id, { type: 'invalidate', scope: 'messages', conversationId: id });
    this.events.publish(u.id, { type: 'invalidate', scope: 'conversations', conversationId: id });
    return result;
  }
}
