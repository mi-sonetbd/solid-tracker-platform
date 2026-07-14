import { Injectable, ServiceUnavailableException } from '@nestjs/common';
import { PrismaService } from '../../database/prisma.service';
import type { AuthContext } from '../../identity/common/auth-context';

@Injectable()
export class AutomationIdentityService {
  constructor(private readonly prisma: PrismaService) {}

  async platformAuth(): Promise<AuthContext> {
    const assignment = await this.prisma.roleAssignment.findFirst({
      where: {
        status: 'ACTIVE',
        scopeType: 'PLATFORM',
        user: {
          status: 'ACTIVE',
        },
        role: {
          status: 'ACTIVE',
        },
      },
      orderBy: {
        createdAt: 'asc',
      },
      include: {
        user: true,
        role: true,
      },
    });

    if (!assignment) {
      throw new ServiceUnavailableException(
        'Billing automation requires an active platform role assignment.',
      );
    }

    return {
      userId: assignment.userId,
      sessionId: 'billing-automation',
      userCode: assignment.user.userCode,
      fullName: assignment.user.fullName,
      mobileNumber: assignment.user.mobileNumber,
      roles: [
        {
          code: assignment.role.code,
          scopeType: 'PLATFORM',
          scopeId: assignment.scopeId,
        },
      ],
      permissions: [],
      organizationIds: [assignment.scopeId],
      customerIds: [],
    };
  }
}
