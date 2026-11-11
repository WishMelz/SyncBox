import { Body, Controller, Get, Header, HttpCode, Post, Req, UseGuards } from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { AuthService, type CurrentUser } from './auth.service';
import { AuthGuard, User, type AuthRequest } from './auth.guard';
import { LoginDto, SetupDto } from './auth.dto';

@Controller('auth')
export class AuthController {
  constructor(private readonly auth: AuthService) {}

  @Get('status')
  @Header('Cache-Control', 'no-store')
  status() {
    return this.auth.status();
  }

  @Post('setup')
  @Header('Cache-Control', 'no-store')
  @Throttle({ default: { limit: 5, ttl: 60000 } })
  setup(@Body() dto: SetupDto) {
    return this.auth.setup(dto);
  }

  @Post('login')
  @HttpCode(200)
  @Header('Cache-Control', 'no-store')
  @Throttle({ default: { limit: 10, ttl: 60000 } })
  login(@Body() dto: LoginDto) {
    return this.auth.login(dto);
  }

  @Get('me')
  @UseGuards(AuthGuard)
  @Header('Cache-Control', 'no-store')
  me(@User() user: CurrentUser) {
    return user;
  }

  @Post('logout')
  @UseGuards(AuthGuard)
  @HttpCode(204)
  async logout(@Req() request: AuthRequest) {
    await this.auth.logout(request.token);
  }
}
