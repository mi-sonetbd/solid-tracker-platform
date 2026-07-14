import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../database/prisma.service';
import { AuthContext } from '../common/auth-context';

@Injectable()
export class RolesService {
  constructor(private readonly prisma: PrismaService) {}

  listMine(auth: AuthContext) {
    return this.prisma.roleAssignment.findMany({
      where: {
        userId: auth.userId,
      },
      orderBy: { createdAt: 'asc' },
      select: {
        id: true,
        scopeType: true,
        scopeId: true,
        status: true,
        effectiveFrom: true,
        effectiveUntil: true,
        role: {
          select: {
            id: true,
            code: true,
            name: true,
            description: true,
            status: true,
          },
        },
      },
    });
  }
}
