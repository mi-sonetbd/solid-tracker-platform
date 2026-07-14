import { CanActivate, ExecutionContext, Injectable, UnauthorizedException } from '@nestjs/common';
import { PrismaService } from '../../database/prisma.service';
import { AuthenticatedRequest } from '../common/auth-context';
import { TokenService } from '../common/token.service';
import { AccessControlService } from './access-control.service';

@Injectable()
export class AccessTokenGuard implements CanActivate {
  constructor(
    private readonly tokenService: TokenService,
    private readonly prisma: PrismaService,
    private readonly accessControlService: AccessControlService,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest<AuthenticatedRequest>();
    const token = this.extractBearerToken(request);

    let payload;

    try {
      payload = await this.tokenService.verifyAccessToken(token);
    } catch {
      throw new UnauthorizedException('Access token is invalid or expired.');
    }

    if (payload.typ !== 'access') {
      throw new UnauthorizedException('Access token type is invalid.');
    }

    const session = await this.prisma.userSession.findUnique({
      where: { id: payload.sid },
      include: {
        user: {
          select: {
            id: true,
            status: true,
          },
        },
      },
    });

    const now = new Date();

    if (
      !session ||
      session.userId !== payload.sub ||
      session.status !== 'ACTIVE' ||
      session.expiresAt <= now ||
      session.user.status !== 'ACTIVE'
    ) {
      throw new UnauthorizedException('Authentication session is not active.');
    }

    request.auth = await this.accessControlService.buildContext(session.userId, session.id);

    return true;
  }

  private extractBearerToken(request: AuthenticatedRequest): string {
    const authorization = request.headers.authorization;

    if (!authorization) {
      throw new UnauthorizedException('Bearer token is required.');
    }

    const [scheme, token] = authorization.split(' ');

    if (scheme !== 'Bearer' || !token) {
      throw new UnauthorizedException('Bearer token is malformed.');
    }

    return token;
  }
}
