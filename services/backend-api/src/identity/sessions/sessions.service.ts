import { ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../../database/prisma.service';
import { AuditService } from '../audit/audit.service';
import { AuthContext } from '../common/auth-context';

@Injectable()
export class SessionsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly auditService: AuditService,
  ) {}

  list(auth: AuthContext) {
    return this.prisma.userSession.findMany({
      where: { userId: auth.userId },
      orderBy: { createdAt: 'desc' },
      select: {
        id: true,
        tokenFamilyId: true,
        deviceName: true,
        platform: true,
        appVersion: true,
        ipAddress: true,
        status: true,
        createdAt: true,
        lastUsedAt: true,
        expiresAt: true,
        revokedAt: true,
        revocationReason: true,
      },
    });
  }

  async revoke(auth: AuthContext, sessionId: string): Promise<void> {
    const session = await this.prisma.userSession.findUnique({
      where: { id: sessionId },
      select: {
        id: true,
        userId: true,
        status: true,
      },
    });

    if (!session) {
      throw new NotFoundException('Session was not found.');
    }

    if (session.userId !== auth.userId) {
      throw new ForbiddenException('Session does not belong to this user.');
    }

    if (session.status === 'ACTIVE') {
      await this.prisma.userSession.update({
        where: { id: session.id },
        data: {
          status: 'REVOKED',
          revokedAt: new Date(),
          revocationReason: 'USER_REVOKED_SESSION',
        },
      });
    }

    await this.auditService.record({
      actorUserId: auth.userId,
      action: 'auth.session.revoked',
      resourceType: 'UserSession',
      resourceId: session.id,
    });
  }
}
