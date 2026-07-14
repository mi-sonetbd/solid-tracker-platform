import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../database/prisma.service';
import { AuthContext } from '../common/auth-context';

@Injectable()
export class MembershipsService {
  constructor(private readonly prisma: PrismaService) {}

  async listMine(auth: AuthContext) {
    const [organizations, customers] = await Promise.all([
      this.prisma.organizationMembership.findMany({
        where: { userId: auth.userId },
        orderBy: { createdAt: 'asc' },
        select: {
          id: true,
          organizationId: true,
          membershipType: true,
          status: true,
          isPrimary: true,
          joinedAt: true,
          endedAt: true,
        },
      }),
      this.prisma.customerMembership.findMany({
        where: { userId: auth.userId },
        orderBy: { createdAt: 'asc' },
        select: {
          id: true,
          customerId: true,
          status: true,
          isPrimary: true,
          joinedAt: true,
          endedAt: true,
        },
      }),
    ]);

    return {
      organizations,
      customers,
    };
  }
}
