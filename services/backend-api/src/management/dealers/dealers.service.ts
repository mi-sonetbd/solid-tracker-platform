import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import type { Prisma } from '../../generated/prisma/client';
import { PrismaService } from '../../database/prisma.service';
import { AuditService } from '../../identity/audit/audit.service';
import type { AuthContext } from '../../identity/common/auth-context';
import { normalizeMobileNumber } from '../../identity/common/mobile-number.util';
import { PasswordService } from '../../identity/common/password.service';
import { ManagementCodeService } from '../common/management-code.service';
import { ManagementContextService } from '../common/management-context.service';
import type { PaginationQueryDto } from '../common/pagination-query.dto';
import type { CreateDealerDto } from './dto/create-dealer.dto';
import type { CreateDealerStaffDto } from './dto/create-dealer-staff.dto';
import type { UpdateDealerDto } from './dto/update-dealer.dto';
import type { UpdateDealerStaffDto } from './dto/update-dealer-staff.dto';

@Injectable()
export class DealersService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly context: ManagementContextService,
    private readonly codes: ManagementCodeService,
    private readonly passwordService: PasswordService,
    private readonly auditService: AuditService,
  ) {}

  async list(auth: AuthContext, query: PaginationQueryDto) {
    const skip = (query.page - 1) * query.pageSize;
    const scopeWhere = this.context.dealerWhere(auth);
    const searchWhere: Prisma.OrganizationWhereInput = query.search
      ? {
          OR: [
            {
              name: {
                contains: query.search,
                mode: 'insensitive',
              },
            },
            {
              code: {
                contains: query.search,
                mode: 'insensitive',
              },
            },
            {
              dealerProfile: {
                dealerCode: {
                  contains: query.search,
                  mode: 'insensitive',
                },
              },
            },
          ],
        }
      : {};

    const where: Prisma.OrganizationWhereInput = {
      AND: [
        scopeWhere,
        searchWhere,
        {
          status: {
            not: 'ARCHIVED',
          },
        },
      ],
    };

    const [items, total] = await Promise.all([
      this.prisma.organization.findMany({
        where,
        skip,
        take: query.pageSize,
        orderBy: {
          createdAt: 'desc',
        },
        include: {
          zone: {
            select: {
              id: true,
              code: true,
              name: true,
            },
          },
          dealerProfile: true,
          _count: {
            select: {
              memberships: true,
              customerGroups: true,
              managedCustomers: true,
            },
          },
        },
      }),
      this.prisma.organization.count({ where }),
    ]);

    return {
      items,
      page: query.page,
      pageSize: query.pageSize,
      total,
      totalPages: Math.ceil(total / query.pageSize),
    };
  }

  async get(auth: AuthContext, dealerId: string) {
    this.context.assertDealer(auth, dealerId);

    const dealer = await this.prisma.organization.findFirst({
      where: {
        id: dealerId,
        type: 'DEALER',
      },
      include: {
        zone: true,
        dealerProfile: true,
        _count: {
          select: {
            memberships: true,
            customerGroups: true,
            managedCustomers: true,
            dealerCommissionEntries: true,
            dealerSettlements: true,
          },
        },
      },
    });

    if (!dealer) {
      throw new NotFoundException('Dealer was not found.');
    }

    return dealer;
  }

  async create(auth: AuthContext, dto: CreateDealerDto) {
    this.context.assertPlatform(auth);

    if (dto.zoneId) {
      const zoneExists = await this.prisma.zone.count({
        where: {
          id: dto.zoneId,
          status: 'ACTIVE',
        },
      });

      if (zoneExists !== 1) {
        throw new BadRequestException('Selected zone does not exist or is not active.');
      }
    }

    const dealer = await this.prisma.$transaction(async (transaction) => {
      const organization = await transaction.organization.create({
        data: {
          code: this.codes.dealer(),
          type: 'DEALER',
          name: dto.name.trim(),
          legalName: dto.legalName?.trim(),
          zoneId: dto.zoneId,
          status: 'ACTIVE',
          dealerProfile: {
            create: {
              dealerCode: this.codes.dealerProfile(),
              tradeLicenseNumber: dto.tradeLicenseNumber?.trim(),
              taxIdentificationNumber: dto.taxIdentificationNumber?.trim(),
              contactMobile: dto.contactMobile?.trim(),
              contactEmail: dto.contactEmail?.trim().toLowerCase(),
              commissionEnabled: dto.commissionEnabled ?? true,
            },
          },
        },
        include: {
          zone: true,
          dealerProfile: true,
        },
      });

      return organization;
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.context.actorOrganizationId(auth),
      action: 'dealer.created',
      resourceType: 'Organization',
      resourceId: dealer.id,
      scopeType: 'DEALER',
      scopeId: dealer.id,
      afterData: dealer,
    });

    return dealer;
  }

  async update(auth: AuthContext, dealerId: string, dto: UpdateDealerDto) {
    this.context.assertPlatform(auth);

    const before = await this.get(auth, dealerId);

    if (dto.zoneId) {
      const zoneExists = await this.prisma.zone.count({
        where: {
          id: dto.zoneId,
          status: 'ACTIVE',
        },
      });

      if (zoneExists !== 1) {
        throw new BadRequestException('Selected zone does not exist or is not active.');
      }
    }

    const updated = await this.prisma.organization.update({
      where: {
        id: dealerId,
      },
      data: {
        name: dto.name?.trim(),
        legalName: dto.legalName?.trim(),
        zoneId: dto.zoneId,
        status: dto.status,
        archivedAt: dto.status === 'ARCHIVED' ? new Date() : dto.status ? null : undefined,
        dealerProfile: {
          update: {
            tradeLicenseNumber: dto.tradeLicenseNumber?.trim(),
            taxIdentificationNumber: dto.taxIdentificationNumber?.trim(),
            contactMobile: dto.contactMobile?.trim(),
            contactEmail: dto.contactEmail?.trim().toLowerCase(),
            commissionEnabled: dto.commissionEnabled,
          },
        },
      },
      include: {
        zone: true,
        dealerProfile: true,
      },
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.context.actorOrganizationId(auth),
      action: 'dealer.updated',
      resourceType: 'Organization',
      resourceId: dealerId,
      scopeType: 'DEALER',
      scopeId: dealerId,
      beforeData: before,
      afterData: updated,
    });

    return updated;
  }

  async listStaff(auth: AuthContext, dealerId: string) {
    this.context.assertDealer(auth, dealerId);
    await this.context.assertDealerExists(dealerId);

    return this.prisma.organizationMembership.findMany({
      where: {
        organizationId: dealerId,
      },
      orderBy: {
        createdAt: 'asc',
      },
      include: {
        user: {
          select: {
            id: true,
            userCode: true,
            fullName: true,
            mobileNumber: true,
            email: true,
            status: true,
            lastLoginAt: true,
          },
        },
        roleAssignments: {
          where: {
            scopeType: 'DEALER',
            scopeId: dealerId,
          },
          include: {
            role: {
              select: {
                id: true,
                code: true,
                name: true,
              },
            },
          },
        },
      },
    });
  }

  async createStaff(auth: AuthContext, dealerId: string, dto: CreateDealerStaffDto) {
    this.context.assertDealer(auth, dealerId);
    await this.context.assertDealerExists(dealerId);

    const normalizedMobileNumber = normalizeMobileNumber(dto.mobileNumber);

    const role = await this.prisma.role.findUnique({
      where: {
        code: dto.roleCode,
      },
    });

    if (!role || role.status !== 'ACTIVE') {
      throw new BadRequestException('Selected dealer role is not active.');
    }

    const existingUser = await this.prisma.user.findUnique({
      where: {
        normalizedMobileNumber,
      },
    });

    if (existingUser?.status === 'ARCHIVED') {
      throw new ConflictException('The mobile number belongs to an archived user.');
    }

    if (!existingUser && !dto.password) {
      throw new BadRequestException('A strong password is required for a new dealer user.');
    }

    const passwordHash = dto.password ? await this.passwordService.hash(dto.password) : undefined;

    const result = await this.prisma.$transaction(async (transaction) => {
      const user = existingUser
        ? existingUser
        : await transaction.user.create({
            data: {
              userCode: this.codes.user(),
              fullName: dto.fullName.trim(),
              mobileNumber: dto.mobileNumber.trim(),
              normalizedMobileNumber,
              email: dto.email?.trim(),
              normalizedEmail: dto.email?.trim().toLowerCase(),
              passwordHash,
              passwordChangedAt: new Date(),
              mobileVerifiedAt: new Date(),
              status: 'ACTIVE',
            },
          });

      const membership = await transaction.organizationMembership.upsert({
        where: {
          organizationId_userId: {
            organizationId: dealerId,
            userId: user.id,
          },
        },
        update: {
          membershipType: dto.roleCode === 'DEALER_OWNER' ? 'OWNER' : 'EMPLOYEE',
          status: 'ACTIVE',
          joinedAt: new Date(),
          endedAt: null,
          invitedByUserId: auth.userId,
        },
        create: {
          organizationId: dealerId,
          userId: user.id,
          membershipType: dto.roleCode === 'DEALER_OWNER' ? 'OWNER' : 'EMPLOYEE',
          status: 'ACTIVE',
          isPrimary: false,
          invitedByUserId: auth.userId,
          joinedAt: new Date(),
        },
      });

      const assignment = await transaction.roleAssignment.upsert({
        where: {
          userId_roleId_scopeType_scopeId: {
            userId: user.id,
            roleId: role.id,
            scopeType: 'DEALER',
            scopeId: dealerId,
          },
        },
        update: {
          organizationMembershipId: membership.id,
          status: 'ACTIVE',
          effectiveFrom: new Date(),
          effectiveUntil: null,
          assignedByUserId: auth.userId,
          revokedByUserId: null,
          revokedAt: null,
          revocationReason: null,
        },
        create: {
          userId: user.id,
          roleId: role.id,
          organizationMembershipId: membership.id,
          scopeType: 'DEALER',
          scopeId: dealerId,
          status: 'ACTIVE',
          assignedByUserId: auth.userId,
        },
      });

      return {
        user: {
          id: user.id,
          userCode: user.userCode,
          fullName: user.fullName,
          mobileNumber: user.mobileNumber,
          email: user.email,
          status: user.status,
        },
        membership,
        roleAssignment: assignment,
      };
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.context.actorOrganizationId(auth),
      action: 'dealer.staff.provisioned',
      resourceType: 'User',
      resourceId: result.user.id,
      scopeType: 'DEALER',
      scopeId: dealerId,
      afterData: {
        user: result.user,
        membershipId: result.membership.id,
        roleCode: dto.roleCode,
      },
      metadata: {
        administrativelyProvisioned: !existingUser,
      },
    });

    return result;
  }

  async updateStaff(
    auth: AuthContext,
    dealerId: string,
    userId: string,
    dto: UpdateDealerStaffDto,
  ) {
    this.context.assertDealer(auth, dealerId);
    await this.context.assertDealerExists(dealerId);

    const membership = await this.prisma.organizationMembership.findUnique({
      where: {
        organizationId_userId: {
          organizationId: dealerId,
          userId,
        },
      },
    });

    if (!membership) {
      throw new NotFoundException('Dealer staff membership was not found.');
    }

    const now = new Date();

    await this.prisma.$transaction(async (transaction) => {
      await transaction.organizationMembership.update({
        where: {
          id: membership.id,
        },
        data: dto.active
          ? {
              status: 'ACTIVE',
              joinedAt: membership.joinedAt ?? now,
              endedAt: null,
            }
          : {
              status: 'SUSPENDED',
            },
      });

      await transaction.roleAssignment.updateMany({
        where: {
          userId,
          scopeType: 'DEALER',
          scopeId: dealerId,
        },
        data: dto.active
          ? {
              status: 'ACTIVE',
              effectiveUntil: null,
              revokedByUserId: null,
              revokedAt: null,
              revocationReason: null,
            }
          : {
              status: 'SUSPENDED',
              effectiveUntil: now,
              revokedByUserId: auth.userId,
              revokedAt: now,
              revocationReason: 'DEALER_STAFF_SUSPENDED',
            },
      });
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.context.actorOrganizationId(auth),
      action: dto.active ? 'dealer.staff.activated' : 'dealer.staff.suspended',
      resourceType: 'OrganizationMembership',
      resourceId: membership.id,
      scopeType: 'DEALER',
      scopeId: dealerId,
      metadata: {
        userId,
      },
    });

    return this.listStaff(auth, dealerId);
  }
}
