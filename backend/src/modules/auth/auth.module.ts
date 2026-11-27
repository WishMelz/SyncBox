import { Module } from '@nestjs/common';
import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';
import { AuthGuard } from './auth.guard';
import { PresenceTracker } from './presence.tracker';

@Module({
  controllers: [AuthController],
  providers: [AuthService, AuthGuard, PresenceTracker],
  exports: [AuthGuard, AuthService, PresenceTracker],
})
export class AuthModule {}
