import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { MessagesService } from '../messages/messages.service';
import { ConversationsService } from './conversations.service';
import { ConversationsController } from './conversations.controller';
@Module({
  imports: [AuthModule],
  controllers: [ConversationsController],
  providers: [ConversationsService, MessagesService],
})
export class ConversationsModule {}
