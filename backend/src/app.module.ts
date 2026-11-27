import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { ThrottlerModule } from '@nestjs/throttler';
import { SettingsModule } from './modules/settings/settings.module';
import { ConversationsModule } from './modules/conversations/conversations.module';
import { DevicesModule } from './modules/devices/devices.module';
import { AuthModule } from './modules/auth/auth.module';
import { MessagesModule } from './modules/messages/messages.module';
import { validateEnvironment } from './config/env';
import { DatabaseModule } from './database/database.module';
import { HealthModule } from './modules/health/health.module';
import { EventsModule } from './events/events.module';
import { SyncEventsModule } from './modules/events/events.module';

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true, validate: validateEnvironment }),
    ThrottlerModule.forRoot([{ ttl: 60000, limit: 10 }]),
    AuthModule,
    SettingsModule,
    MessagesModule,
    ConversationsModule,
    DevicesModule,
    DatabaseModule,
    HealthModule,
    EventsModule,
    SyncEventsModule,
  ],
})
export class AppModule {}
