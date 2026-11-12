import {
  CanActivate,
  ExecutionContext,
  Injectable,
  UnauthorizedException,
  createParamDecorator,
} from '@nestjs/common';
import { AuthService, type CurrentUser } from './auth.service';

export interface AuthRequest {
  headers: { authorization?: string };
  user: CurrentUser;
  token: string;
}
@Injectable()
export class AuthGuard implements CanActivate {
  constructor(private readonly auth: AuthService) {}
  async canActivate(context: ExecutionContext) {
    const request = context.switchToHttp().getRequest<AuthRequest>();
    const match = /^Bearer ([a-f0-9]{64})$/i.exec(request.headers.authorization ?? '');
    if (!match?.[1]) throw new UnauthorizedException('请先登录');
    request.token = match[1];
    request.user = await this.auth.authenticate(match[1]);
    return true;
  }
}
export const User = createParamDecorator(
  (_data: unknown, context: ExecutionContext): CurrentUser =>
    context.switchToHttp().getRequest<AuthRequest>().user,
);
