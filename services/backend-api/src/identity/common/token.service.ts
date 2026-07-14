import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { createHmac, randomBytes } from 'node:crypto';

export interface AccessTokenPayload {
  sub: string;
  sid: string;
  typ: 'access';
}

@Injectable()
export class TokenService {
  private readonly accessSecret: string;
  private readonly refreshPepper: string;
  private readonly accessTtlSeconds: number;
  private readonly refreshTtlSeconds: number;

  constructor(
    private readonly jwtService: JwtService,
    configService: ConfigService,
  ) {
    this.accessSecret = configService.getOrThrow<string>('AUTH_JWT_ACCESS_SECRET');
    this.refreshPepper = configService.getOrThrow<string>('AUTH_REFRESH_TOKEN_PEPPER');
    this.accessTtlSeconds = configService.get<number>('AUTH_ACCESS_TOKEN_TTL_SECONDS', 900);
    this.refreshTtlSeconds = configService.get<number>('AUTH_REFRESH_TOKEN_TTL_SECONDS', 2592000);
  }

  async signAccessToken(userId: string, sessionId: string): Promise<string> {
    return this.jwtService.signAsync(
      {
        sub: userId,
        sid: sessionId,
        typ: 'access',
      } satisfies AccessTokenPayload,
      {
        secret: this.accessSecret,
        expiresIn: this.accessTtlSeconds,
      },
    );
  }

  async verifyAccessToken(token: string): Promise<AccessTokenPayload> {
    return this.jwtService.verifyAsync<AccessTokenPayload>(token, {
      secret: this.accessSecret,
    });
  }

  createRefreshToken(): string {
    return randomBytes(48).toString('base64url');
  }

  hashRefreshToken(token: string): string {
    return createHmac('sha256', this.refreshPepper).update(token).digest('hex');
  }

  getRefreshExpiry(now = new Date()): Date {
    return new Date(now.getTime() + this.refreshTtlSeconds * 1000);
  }

  get accessTokenExpiresInSeconds(): number {
    return this.accessTtlSeconds;
  }
}
