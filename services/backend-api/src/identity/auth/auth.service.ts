import { Injectable, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { randomUUID } from 'node:crypto';
import { PrismaService } from '../../database/prisma.service';
import { AccessControlService } from '../access-control/access-control.service';
import { AuditService } from '../audit/audit.service';
import { AuthContext } from '../common/auth-context';
import { AuthRateLimitService } from '../common/auth-rate-limit.service';
import { normalizeMobileNumber } from '../common/mobile-number.util';
import { PasswordService } from '../common/password.service';
import { TokenService } from '../common/token.service';
import { LoginDto } from './dto/login.dto';

export interface RequestMetadata {
  ipAddress: string;
  userAgent?: string;
}

export interface AuthTokenResponse {
  tokenType: 'Bearer';
  accessToken: string;
  accessTokenExpiresIn: number;
  refreshToken: string;
  sessionId: string;
}

@Injectable()
export class AuthService {
  private readonly maxFailedAttempts: number;
  private readonly lockoutSeconds: number;

  constructor(
    private readonly prisma: PrismaService,
    private readonly passwordService: PasswordService,
    private readonly tokenService: TokenService,
    private readonly rateLimitService: AuthRateLimitService,
    private readonly accessControlService: AccessControlService,
    private readonly auditService: AuditService,
    configService: ConfigService,
  ) {
    this.maxFailedAttempts = configService.get<number>('AUTH_MAX_FAILED_ATTEMPTS', 5);
    this.lockoutSeconds = configService.get<number>('AUTH_LOCKOUT_SECONDS', 900);
  }

  async login(dto: LoginDto, metadata: RequestMetadata): Promise<AuthTokenResponse> {
    const normalizedMobileNumber = normalizeMobileNumber(dto.mobileNumber);

    await this.rateLimitService.consumeLoginAttempt(metadata.ipAddress, normalizedMobileNumber);

    let user = await this.prisma.user.findUnique({
      where: { normalizedMobileNumber },
    });

    if (!user) {
      throw this.invalidCredentials();
    }

    const now = new Date();

    if (user.status === 'LOCKED' && user.lockedUntil && user.lockedUntil <= now) {
      user = await this.prisma.user.update({
        where: { id: user.id },
        data: {
          status: 'ACTIVE',
          failedLoginCount: 0,
          lockedUntil: null,
        },
      });
    }

    if (
      user.status !== 'ACTIVE' ||
      !user.passwordHash ||
      (user.lockedUntil && user.lockedUntil > now)
    ) {
      throw this.invalidCredentials();
    }

    const passwordValid = await this.passwordService.verify(dto.password, user.passwordHash);

    if (!passwordValid) {
      await this.registerFailedLogin(user.id, user.failedLoginCount);
      throw this.invalidCredentials();
    }

    await this.prisma.user.update({
      where: { id: user.id },
      data: {
        failedLoginCount: 0,
        lockedUntil: null,
        lastLoginAt: now,
      },
    });

    await this.rateLimitService.clearMobileLoginAttempts(normalizedMobileNumber);

    const tokenResponse = await this.createSession(
      user.id,
      randomUUID(),
      dto.platform,
      dto.deviceName,
      dto.appVersion,
      metadata,
    );

    await this.auditService.record({
      actorUserId: user.id,
      action: 'auth.login.succeeded',
      resourceType: 'UserSession',
      resourceId: tokenResponse.sessionId,
      ipAddress: metadata.ipAddress,
      userAgent: metadata.userAgent,
    });

    return tokenResponse;
  }

  async refresh(refreshToken: string, metadata: RequestMetadata): Promise<AuthTokenResponse> {
    const refreshTokenHash = this.tokenService.hashRefreshToken(refreshToken);

    const session = await this.prisma.userSession.findUnique({
      where: { refreshTokenHash },
      include: {
        user: true,
      },
    });

    if (!session) {
      throw new UnauthorizedException('Refresh token is invalid.');
    }

    const now = new Date();

    if (
      session.status !== 'ACTIVE' ||
      session.expiresAt <= now ||
      session.user.status !== 'ACTIVE'
    ) {
      await this.revokeTokenFamily(session.tokenFamilyId, 'REFRESH_TOKEN_REUSE_OR_EXPIRED');

      throw new UnauthorizedException('Refresh token is no longer active.');
    }

    const nextRefreshToken = this.tokenService.createRefreshToken();
    const nextRefreshTokenHash = this.tokenService.hashRefreshToken(nextRefreshToken);

    const nextSession = await this.prisma.$transaction(async (transaction) => {
      const claimed = await transaction.userSession.updateMany({
        where: {
          id: session.id,
          status: 'ACTIVE',
        },
        data: {
          status: 'REVOKED',
          revokedAt: now,
          revocationReason: 'ROTATED',
          lastUsedAt: now,
        },
      });

      if (claimed.count !== 1) {
        throw new UnauthorizedException('Refresh token has already been used.');
      }

      return transaction.userSession.create({
        data: {
          userId: session.userId,
          tokenFamilyId: session.tokenFamilyId,
          refreshTokenHash: nextRefreshTokenHash,
          deviceName: session.deviceName,
          platform: session.platform,
          appVersion: session.appVersion,
          ipAddress: metadata.ipAddress,
          userAgent: metadata.userAgent,
          expiresAt: this.tokenService.getRefreshExpiry(now),
        },
      });
    });

    const accessToken = await this.tokenService.signAccessToken(session.userId, nextSession.id);

    await this.auditService.record({
      actorUserId: session.userId,
      action: 'auth.session.refreshed',
      resourceType: 'UserSession',
      resourceId: nextSession.id,
      metadata: {
        previousSessionId: session.id,
        tokenFamilyId: session.tokenFamilyId,
      },
      ipAddress: metadata.ipAddress,
      userAgent: metadata.userAgent,
    });

    return {
      tokenType: 'Bearer',
      accessToken,
      accessTokenExpiresIn: this.tokenService.accessTokenExpiresInSeconds,
      refreshToken: nextRefreshToken,
      sessionId: nextSession.id,
    };
  }

  async logout(auth: AuthContext, metadata: RequestMetadata): Promise<void> {
    const now = new Date();

    await this.prisma.userSession.updateMany({
      where: {
        id: auth.sessionId,
        userId: auth.userId,
        status: 'ACTIVE',
      },
      data: {
        status: 'REVOKED',
        revokedAt: now,
        revocationReason: 'USER_LOGOUT',
      },
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      action: 'auth.logout',
      resourceType: 'UserSession',
      resourceId: auth.sessionId,
      ipAddress: metadata.ipAddress,
      userAgent: metadata.userAgent,
    });
  }

  async logoutAll(auth: AuthContext, metadata: RequestMetadata): Promise<number> {
    const now = new Date();

    const result = await this.prisma.userSession.updateMany({
      where: {
        userId: auth.userId,
        status: 'ACTIVE',
      },
      data: {
        status: 'REVOKED',
        revokedAt: now,
        revocationReason: 'USER_LOGOUT_ALL',
      },
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      action: 'auth.logout_all',
      resourceType: 'UserSession',
      metadata: {
        revokedSessionCount: result.count,
      },
      ipAddress: metadata.ipAddress,
      userAgent: metadata.userAgent,
    });

    return result.count;
  }

  async getMe(auth: AuthContext): Promise<AuthContext> {
    return this.accessControlService.buildContext(auth.userId, auth.sessionId);
  }

  private async createSession(
    userId: string,
    tokenFamilyId: string,
    platform: LoginDto['platform'],
    deviceName: string | undefined,
    appVersion: string | undefined,
    metadata: RequestMetadata,
  ): Promise<AuthTokenResponse> {
    const refreshToken = this.tokenService.createRefreshToken();

    const session = await this.prisma.userSession.create({
      data: {
        userId,
        tokenFamilyId,
        refreshTokenHash: this.tokenService.hashRefreshToken(refreshToken),
        platform,
        deviceName,
        appVersion,
        ipAddress: metadata.ipAddress,
        userAgent: metadata.userAgent,
        expiresAt: this.tokenService.getRefreshExpiry(),
      },
    });

    const accessToken = await this.tokenService.signAccessToken(userId, session.id);

    return {
      tokenType: 'Bearer',
      accessToken,
      accessTokenExpiresIn: this.tokenService.accessTokenExpiresInSeconds,
      refreshToken,
      sessionId: session.id,
    };
  }

  private async registerFailedLogin(userId: string, currentFailedCount: number): Promise<void> {
    const nextFailedCount = currentFailedCount + 1;
    const shouldLock = nextFailedCount >= this.maxFailedAttempts;

    await this.prisma.user.update({
      where: { id: userId },
      data: {
        failedLoginCount: nextFailedCount,
        status: shouldLock ? 'LOCKED' : undefined,
        lockedUntil: shouldLock ? new Date(Date.now() + this.lockoutSeconds * 1000) : undefined,
      },
    });
  }

  private async revokeTokenFamily(tokenFamilyId: string, reason: string): Promise<void> {
    await this.prisma.userSession.updateMany({
      where: {
        tokenFamilyId,
        status: 'ACTIVE',
      },
      data: {
        status: 'REVOKED',
        revokedAt: new Date(),
        revocationReason: reason,
      },
    });
  }

  private invalidCredentials(): UnauthorizedException {
    return new UnauthorizedException('Mobile number or password is invalid.');
  }
}
