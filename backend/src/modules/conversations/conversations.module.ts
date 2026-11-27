import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { MessagesService } from '../messages/messages.service';
import { ConversationsService } from './conversations.service';
import { ConversationsController } from './conversations.controller';
import { ContentLengthGuard } from './content-length.guard';

@Module({
  imports: [AuthModule],
  controllers: [ConversationsController],
  providers: [ConversationsService, MessagesService, ContentLengthGuard],
})
export class ConversationsModule {}
