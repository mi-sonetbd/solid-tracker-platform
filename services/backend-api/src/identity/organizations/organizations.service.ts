import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../database/prisma.service';
import { AuthContext } from '../common/auth-context';

@Injectable()
export class OrganizationsService {
  constructor(private readonly prisma: PrismaService) {}

  listMine(auth: AuthContext) {
    return this.prisma.organizationMembership.findMany({
      where: {
        userId: auth.userId,
      },
      orderBy: [{ status: 'asc' }, { createdAt: 'asc' }],
      select: {
        id: true,
        membershipType: true,
        status: true,
        isPrimary: true,
        joinedAt: true,
        endedAt: true,
        organization: {
          select: {
            id: true,
            code: true,
            type: true,
            name: true,
            legalName: true,
            status: true,
            zoneId: true,
          },
        },
      },
    });
  }
}
