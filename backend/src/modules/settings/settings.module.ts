import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { SettingsService } from './settings.service';
import { SettingsController } from './settings.controller';
import { SecurityRateLimitService } from './security-rate-limit.service';

@Module({
  imports: [AuthModule],
  providers: [SettingsService, SecurityRateLimitService],
  controllers: [SettingsController],
})
export class SettingsModule {}
