import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../database/prisma.service';
import { AuthContext, AuthenticatedRole } from '../common/auth-context';

@Injectable()
export class AccessControlService {
  constructor(private readonly prisma: PrismaService) {}

  async buildContext(userId: string, sessionId: string): Promise<AuthContext> {
    const now = new Date();

    const [user, assignments, organizationMemberships, customerMemberships] = await Promise.all([
      this.prisma.user.findUniqueOrThrow({
        where: { id: userId },
        select: {
          id: true,
          userCode: true,
          fullName: true,
          mobileNumber: true,
        },
      }),
      this.prisma.roleAssignment.findMany({
        where: {
          userId,
          status: 'ACTIVE',
          effectiveFrom: { lte: now },
          OR: [{ effectiveUntil: null }, { effectiveUntil: { gt: now } }],
          role: {
            status: 'ACTIVE',
          },
        },
        include: {
          role: {
            include: {
              permissions: {
                include: {
                  permission: true,
                },
              },
            },
          },
        },
      }),
      this.prisma.organizationMembership.findMany({
        where: {
          userId,
          status: 'ACTIVE',
        },
        select: {
          organizationId: true,
        },
      }),
      this.prisma.customerMembership.findMany({
        where: {
          userId,
          status: 'ACTIVE',
        },
        select: {
          customerId: true,
        },
      }),
    ]);

    const roles: AuthenticatedRole[] = assignments.map((assignment) => ({
      code: assignment.role.code,
      scopeType: assignment.scopeType,
      scopeId: assignment.scopeId,
    }));

    const permissions = Array.from(
      new Set(
        assignments.flatMap((assignment) =>
          assignment.role.permissions
            .filter((rolePermission) => rolePermission.permission.status === 'ACTIVE')
            .map((rolePermission) => rolePermission.permission.code),
        ),
      ),
    ).sort();

    return {
      userId: user.id,
      sessionId,
      userCode: user.userCode,
      fullName: user.fullName,
      mobileNumber: user.mobileNumber,
      roles,
      permissions,
      organizationIds: organizationMemberships.map((membership) => membership.organizationId),
      customerIds: customerMemberships.map((membership) => membership.customerId),
    };
  }
}
