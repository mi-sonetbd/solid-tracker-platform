import { BadRequestException, Injectable, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createHmac, randomInt, randomUUID, timingSafeEqual } from 'node:crypto';
import { PrismaService } from '../../database/prisma.service';
import { normalizeMobileNumber } from '../common/mobile-number.util';

export interface OtpIssueInput {
  userId?: string;
  mobileNumber: string;
  purpose: 'MOBILE_VERIFICATION' | 'PASSWORD_RESET' | 'HIGH_RISK_ACTION';
  requestIp?: string;
  requestUserAgent?: string;
}

export interface OtpIssueResult {
  challengeId: string;
  code: string;
  expiresAt: Date;
}

@Injectable()
export class OtpService {
  private readonly pepper: string;
  private readonly ttlSeconds: number;
  private readonly maxAttempts: number;

  constructor(
    private readonly prisma: PrismaService,
    configService: ConfigService,
  ) {
    this.pepper = configService.getOrThrow<string>('AUTH_OTP_PEPPER');
    this.ttlSeconds = configService.get<number>('AUTH_OTP_TTL_SECONDS', 300);
    this.maxAttempts = configService.get<number>('AUTH_OTP_MAX_ATTEMPTS', 5);
  }

  async issue(input: OtpIssueInput): Promise<OtpIssueResult> {
    const normalizedMobileNumber = normalizeMobileNumber(input.mobileNumber);
    const challengeId = randomUUID();
    const code = randomInt(100000, 1000000).toString();
    const now = new Date();
    const expiresAt = new Date(now.getTime() + this.ttlSeconds * 1000);

    await this.prisma.$transaction(async (transaction) => {
      await transaction.otpChallenge.updateMany({
        where: {
          normalizedMobileNumber,
          purpose: input.purpose,
          status: 'PENDING',
        },
        data: {
          status: 'CANCELLED',
          invalidatedAt: now,
        },
      });

      await transaction.otpChallenge.create({
        data: {
          id: challengeId,
          userId: input.userId,
          normalizedMobileNumber,
          purpose: input.purpose,
          codeHash: this.hashCode(challengeId, code),
          maxAttempts: this.maxAttempts,
          expiresAt,
          requestIp: input.requestIp,
          requestUserAgent: input.requestUserAgent,
        },
      });
    });

    return {
      challengeId,
      code,
      expiresAt,
    };
  }

  async verify(challengeId: string, code: string): Promise<void> {
    if (!/^\d{6}$/.test(code)) {
      throw new BadRequestException('OTP code format is invalid.');
    }

    const challenge = await this.prisma.otpChallenge.findUnique({
      where: { id: challengeId },
    });

    if (!challenge || challenge.status !== 'PENDING') {
      throw new UnauthorizedException('OTP challenge is not active.');
    }

    const now = new Date();

    if (challenge.expiresAt <= now) {
      await this.prisma.otpChallenge.update({
        where: { id: challenge.id },
        data: {
          status: 'EXPIRED',
          invalidatedAt: now,
        },
      });

      throw new UnauthorizedException('OTP challenge has expired.');
    }

    const expected = Buffer.from(challenge.codeHash, 'hex');
    const actual = Buffer.from(this.hashCode(challenge.id, code), 'hex');
    const valid = expected.length === actual.length && timingSafeEqual(expected, actual);

    if (!valid) {
      const attemptCount = challenge.attemptCount + 1;
      const locked = attemptCount >= challenge.maxAttempts;

      await this.prisma.otpChallenge.update({
        where: { id: challenge.id },
        data: {
          attemptCount,
          status: locked ? 'LOCKED' : 'PENDING',
          invalidatedAt: locked ? now : null,
        },
      });

      throw new UnauthorizedException('OTP code is invalid.');
    }

    await this.prisma.otpChallenge.update({
      where: { id: challenge.id },
      data: {
        status: 'VERIFIED',
        verifiedAt: now,
      },
    });
  }

  private hashCode(challengeId: string, code: string): string {
    return createHmac('sha256', this.pepper).update(`${challengeId}:${code}`).digest('hex');
  }
}
