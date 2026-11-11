import { BrowserFingerprint1794000000010 } from './migrations/1794000000010-browser-fingerprint';
import { MessageIdempotency1794000000011 } from './migrations/1794000000011-message-idempotency';
import { MessageSearch1794000000012 } from './migrations/1794000000012-message-search';
import { DeviceIdentity1794000000009 } from './migrations/1794000000009-device-identity';
import { Annotations1794000000008 } from './migrations/1794000000008-annotations';
import { Pinned1794000000007 } from './migrations/1794000000007-pinned';
import { Settings1794000000006 } from './migrations/1794000000006-settings';
import { Attachments1794000000005 } from './migrations/1794000000005-attachments';
import { Images1794000000004 } from './migrations/1794000000004-images';
import { SingleUser1794000000003 } from './migrations/1794000000003-single-user';
import { Conversations1794000000002 } from './migrations/1794000000002-conversations';
import { Devices1794000000001 } from './migrations/1794000000001-devices';
import { InitialMessaging1794000000000 } from './migrations/1794000000000-initial-messaging';
import { DatabaseService } from './database.service';
import { Global, Module } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { TypeOrmModule } from '@nestjs/typeorm';
import { mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';

@Global()
@Module({
  providers: [DatabaseService],
  exports: [DatabaseService],
  imports: [
    TypeOrmModule.forRootAsync({
      inject: [ConfigService],
      useFactory: (config: ConfigService) => {
        const configuredPath = config.getOrThrow<string>('DATABASE_PATH');
        const database = configuredPath === ':memory:' ? configuredPath : resolve(configuredPath);
        if (database !== ':memory:') mkdirSync(dirname(database), { recursive: true });
        return {
          type: 'better-sqlite3' as const,
          database,
          autoLoadEntities: true,
          synchronize: false,
          migrations: [
            InitialMessaging1794000000000,
            Devices1794000000001,
            Conversations1794000000002,
            SingleUser1794000000003,
            Images1794000000004,
            Attachments1794000000005,
            Settings1794000000006,
            Pinned1794000000007,
            Annotations1794000000008,
            DeviceIdentity1794000000009,
            BrowserFingerprint1794000000010,
            MessageIdempotency1794000000011,
            MessageSearch1794000000012,
          ],
          migrationsRun: true,
          retryAttempts: 1,
          prepareDatabase: (connection: { pragma: (sql: string) => unknown }) => {
            connection.pragma('journal_mode = WAL');
            connection.pragma('foreign_keys = ON');
            connection.pragma('busy_timeout = 5000');
          },
        };
      },
    }),
  ],
})
export class DatabaseModule {}
