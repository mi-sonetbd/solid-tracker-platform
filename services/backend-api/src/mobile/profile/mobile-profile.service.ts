import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../../database/prisma.service';
import type { AuthContext } from '../../identity/common/auth-context';
import { MobileAccessService } from '../common/mobile-access.service';
import { mobileJsonSafe } from '../common/mobile-json.util';

@Injectable()
export class MobileProfileService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly access: MobileAccessService,
  ) {}

  async profile(auth: AuthContext) {
    const customerIds = this.access.customerIds(auth);
    const user = await this.prisma.user.findUnique({
      where: {
        id: auth.userId,
      },
      select: {
        id: true,
        userCode: true,
        fullName: true,
        mobileNumber: true,
        email: true,
        mobileVerifiedAt: true,
        emailVerifiedAt: true,
        lastLoginAt: true,
        customerMemberships: {
          where: {
            customerId: {
              in: customerIds,
            },
            status: 'ACTIVE',
            endedAt: null,
          },
          orderBy: {
            createdAt: 'asc',
          },
          select: {
            id: true,
            isPrimary: true,
            joinedAt: true,
            customer: {
              select: {
                id: true,
                customerCode: true,
                customerType: true,
                status: true,
                primaryMobile: true,
                primaryEmail: true,
                managingDealer: {
                  select: {
                    id: true,
                    code: true,
                    name: true,
                  },
                },
                individualProfile: {
                  select: {
                    fullName: true,
                    emergencyContactName: true,
                    emergencyContactMobile: true,
                  },
                },
                organizationProfile: {
                  select: {
                    legalName: true,
                    displayName: true,
                    contactPersonName: true,
                    contactMobile: true,
                    contactEmail: true,
                  },
                },
              },
            },
          },
        },
      },
    });

    if (!user) {
      throw new NotFoundException('Authenticated user was not found.');
    }

    return mobileJsonSafe({
      data: user,
      meta: {
        generatedAt: new Date().toISOString(),
      },
    });
  }
}
