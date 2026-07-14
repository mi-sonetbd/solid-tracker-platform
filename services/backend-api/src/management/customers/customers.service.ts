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
import type { AddressDto } from './dto/address.dto';
import type { AssignCustomerGroupDto } from './dto/assign-customer-group.dto';
import type { CreateCustomerMemberDto } from './dto/create-customer-member.dto';
import type { CreateIndividualCustomerDto } from './dto/create-individual-customer.dto';
import type { CreateOrganizationCustomerDto } from './dto/create-organization-customer.dto';
import type { CustomerQueryDto } from './dto/customer-query.dto';
import type { TransferCustomerDto } from './dto/transfer-customer.dto';

@Injectable()
export class CustomersService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly context: ManagementContextService,
    private readonly codes: ManagementCodeService,
    private readonly passwordService: PasswordService,
    private readonly auditService: AuditService,
  ) {}

  async list(auth: AuthContext, query: CustomerQueryDto) {
    const skip = (query.page - 1) * query.pageSize;
    const scopeWhere = this.context.customerWhere(auth);
    const searchWhere: Prisma.CustomerWhereInput = query.search
      ? {
          OR: [
            {
              customerCode: {
                contains: query.search,
                mode: 'insensitive',
              },
            },
            {
              primaryMobile: {
                contains: query.search,
              },
            },
            {
              primaryEmail: {
                contains: query.search,
                mode: 'insensitive',
              },
            },
            {
              individualProfile: {
                fullName: {
                  contains: query.search,
                  mode: 'insensitive',
                },
              },
            },
            {
              organizationProfile: {
                displayName: {
                  contains: query.search,
                  mode: 'insensitive',
                },
              },
            },
          ],
        }
      : {};

    const where: Prisma.CustomerWhereInput = {
      AND: [
        scopeWhere,
        searchWhere,
        query.status
          ? {
              status: query.status,
            }
          : {
              status: {
                not: 'ARCHIVED',
              },
            },
        query.customerType
          ? {
              customerType: query.customerType,
            }
          : {},
        query.managingDealerId
          ? {
              managingDealerId: query.managingDealerId,
            }
          : {},
        query.customerGroupId
          ? {
              customerGroupId: query.customerGroupId,
            }
          : {},
      ],
    };

    const [items, total] = await Promise.all([
      this.prisma.customer.findMany({
        where,
        skip,
        take: query.pageSize,
        orderBy: {
          createdAt: 'desc',
        },
        include: {
          individualProfile: true,
          organizationProfile: true,
          managingDealer: {
            select: {
              id: true,
              code: true,
              name: true,
            },
          },
          customerGroup: {
            select: {
              id: true,
              code: true,
              name: true,
            },
          },
          _count: {
            select: {
              memberships: true,
              vehicles: true,
              billingSubscriptions: true,
            },
          },
        },
      }),
      this.prisma.customer.count({ where }),
    ]);

    return {
      items,
      page: query.page,
      pageSize: query.pageSize,
      total,
      totalPages: Math.ceil(total / query.pageSize),
    };
  }

  async get(auth: AuthContext, customerId: string) {
    await this.context.assertCustomer(auth, customerId);

    const customer = await this.prisma.customer.findUnique({
      where: {
        id: customerId,
      },
      include: {
        individualProfile: true,
        organizationProfile: true,
        managingDealer: {
          include: {
            dealerProfile: true,
          },
        },
        customerGroup: true,
        memberships: {
          include: {
            user: {
              select: {
                id: true,
                userCode: true,
                fullName: true,
                mobileNumber: true,
                email: true,
                status: true,
              },
            },
          },
        },
        dealerAssignments: {
          orderBy: {
            assignedAt: 'desc',
          },
        },
        _count: {
          select: {
            vehicles: true,
            billingSubscriptions: true,
            invoices: true,
            payments: true,
          },
        },
      },
    });

    if (!customer) {
      throw new NotFoundException('Customer was not found.');
    }

    return customer;
  }

  async createIndividual(auth: AuthContext, dto: CreateIndividualCustomerDto) {
    const dealerId = await this.resolveDealer(auth, dto.managingDealerId);

    const groupId = await this.resolveGroup(dealerId, dto.customerGroupId);

    const customer = await this.prisma.$transaction(async (transaction) => {
      return transaction.customer.create({
        data: {
          customerCode: this.codes.customer(),
          customerType: 'INDIVIDUAL',
          status: 'ACTIVE',
          managingDealerId: dealerId,
          customerGroupId: groupId,
          acquisitionSource: dealerId ? 'DEALER' : 'DIRECT',
          primaryMobile: dto.primaryMobile.trim(),
          primaryEmail: dto.primaryEmail?.trim().toLowerCase(),
          billingAddress: this.address(dto.billingAddress),
          createdByUserId: auth.userId,
          individualProfile: {
            create: {
              fullName: dto.fullName.trim(),
              dateOfBirth: dto.dateOfBirth ? new Date(dto.dateOfBirth) : undefined,
              emergencyContactName: dto.emergencyContactName?.trim(),
              emergencyContactMobile: dto.emergencyContactMobile?.trim(),
            },
          },
          dealerAssignments: {
            create: {
              managementType: dealerId ? 'DEALER' : 'PLATFORM',
              dealerOrganizationId: dealerId,
              assignmentReason: 'INITIAL_ASSIGNMENT',
              assignedByUserId: auth.userId,
            },
          },
        },
        include: {
          individualProfile: true,
          managingDealer: true,
          customerGroup: true,
        },
      });
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.context.actorOrganizationId(auth),
      action: 'customer.individual.created',
      resourceType: 'Customer',
      resourceId: customer.id,
      scopeType: 'CUSTOMER',
      scopeId: customer.id,
      afterData: customer,
    });

    return customer;
  }

  async createOrganization(auth: AuthContext, dto: CreateOrganizationCustomerDto) {
    const dealerId = await this.resolveDealer(auth, dto.managingDealerId);

    const groupId = await this.resolveGroup(dealerId, dto.customerGroupId);

    if (dto.registrationNumber) {
      const duplicate = await this.prisma.organizationCustomerProfile.count({
        where: {
          registrationNumber: dto.registrationNumber.trim(),
        },
      });

      if (duplicate > 0) {
        throw new ConflictException('The organization registration number already exists.');
      }
    }

    const customer = await this.prisma.$transaction(async (transaction) => {
      return transaction.customer.create({
        data: {
          customerCode: this.codes.customer(),
          customerType: 'ORGANIZATION',
          status: 'ACTIVE',
          managingDealerId: dealerId,
          customerGroupId: groupId,
          acquisitionSource: dealerId ? 'DEALER' : 'DIRECT',
          primaryMobile: dto.primaryMobile.trim(),
          primaryEmail: dto.primaryEmail?.trim().toLowerCase(),
          billingAddress: this.address(dto.billingAddress),
          createdByUserId: auth.userId,
          organizationProfile: {
            create: {
              legalName: dto.legalName.trim(),
              displayName: dto.displayName.trim(),
              registrationNumber: dto.registrationNumber?.trim(),
              taxReference: dto.taxReference?.trim(),
              contactPersonName: dto.contactPersonName?.trim(),
              contactMobile: dto.contactMobile?.trim(),
              contactEmail: dto.contactEmail?.trim().toLowerCase(),
              operationalAddress: this.address(dto.operationalAddress),
            },
          },
          dealerAssignments: {
            create: {
              managementType: dealerId ? 'DEALER' : 'PLATFORM',
              dealerOrganizationId: dealerId,
              assignmentReason: 'INITIAL_ASSIGNMENT',
              assignedByUserId: auth.userId,
            },
          },
        },
        include: {
          organizationProfile: true,
          managingDealer: true,
          customerGroup: true,
        },
      });
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.context.actorOrganizationId(auth),
      action: 'customer.organization.created',
      resourceType: 'Customer',
      resourceId: customer.id,
      scopeType: 'CUSTOMER',
      scopeId: customer.id,
      afterData: customer,
    });

    return customer;
  }

  async assignGroup(auth: AuthContext, customerId: string, dto: AssignCustomerGroupDto) {
    const customer = await this.context.assertCustomerManagedByDealer(auth, customerId);

    if (!customer.managingDealerId && dto.customerGroupId) {
      throw new BadRequestException('A platform-managed customer cannot belong to a dealer group.');
    }

    const groupId = await this.resolveGroup(
      customer.managingDealerId,
      dto.customerGroupId ?? undefined,
    );

    const updated = await this.prisma.customer.update({
      where: {
        id: customerId,
      },
      data: {
        customerGroupId: groupId,
      },
      include: {
        individualProfile: true,
        organizationProfile: true,
        managingDealer: true,
        customerGroup: true,
      },
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.context.actorOrganizationId(auth),
      action: 'customer.group.changed',
      resourceType: 'Customer',
      resourceId: customerId,
      scopeType: 'CUSTOMER',
      scopeId: customerId,
      beforeData: {
        customerGroupId: customer.customerGroupId,
      },
      afterData: {
        customerGroupId: updated.customerGroupId,
      },
    });

    return updated;
  }

  async transfer(auth: AuthContext, customerId: string, dto: TransferCustomerDto) {
    this.context.assertPlatform(auth);

    const before = await this.get(auth, customerId);
    const targetDealerId = dto.targetDealerId ?? null;

    if (targetDealerId) {
      await this.context.assertDealerExists(targetDealerId);
    }

    const targetGroupId = await this.resolveGroup(
      targetDealerId,
      dto.targetCustomerGroupId ?? undefined,
    );

    const now = new Date();

    const updated = await this.prisma.$transaction(async (transaction) => {
      await transaction.customerDealerAssignment.updateMany({
        where: {
          customerId,
          endedAt: null,
        },
        data: {
          endedAt: now,
        },
      });

      await transaction.customerDealerAssignment.create({
        data: {
          customerId,
          managementType: targetDealerId ? 'DEALER' : 'PLATFORM',
          dealerOrganizationId: targetDealerId,
          assignmentReason: targetDealerId ? 'DEALER_TRANSFER' : 'PLATFORM_ASSIGNMENT',
          assignedByUserId: auth.userId,
          notes: dto.notes?.trim(),
        },
      });

      return transaction.customer.update({
        where: {
          id: customerId,
        },
        data: {
          managingDealerId: targetDealerId,
          customerGroupId: targetGroupId,
        },
        include: {
          individualProfile: true,
          organizationProfile: true,
          managingDealer: true,
          customerGroup: true,
        },
      });
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.context.actorOrganizationId(auth),
      action: 'customer.transferred',
      resourceType: 'Customer',
      resourceId: customerId,
      scopeType: 'CUSTOMER',
      scopeId: customerId,
      beforeData: {
        managingDealerId: before.managingDealerId,
        customerGroupId: before.customerGroupId,
      },
      afterData: {
        managingDealerId: updated.managingDealerId,
        customerGroupId: updated.customerGroupId,
      },
      metadata: {
        notes: dto.notes,
      },
    });

    return updated;
  }

  async listMembers(auth: AuthContext, customerId: string) {
    await this.context.assertCustomer(auth, customerId);

    return this.prisma.customerMembership.findMany({
      where: {
        customerId,
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
      },
    });
  }

  async createMember(auth: AuthContext, customerId: string, dto: CreateCustomerMemberDto) {
    await this.context.assertCustomerManagedByDealer(auth, customerId);

    const normalizedMobileNumber = normalizeMobileNumber(dto.mobileNumber);

    const role = await this.prisma.role.findUnique({
      where: {
        code: dto.roleCode,
      },
    });

    if (!role || role.status !== 'ACTIVE') {
      throw new BadRequestException('Selected customer role is not active.');
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
      throw new BadRequestException('A strong password is required for a new customer user.');
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

      if (dto.isPrimary) {
        await transaction.customerMembership.updateMany({
          where: {
            customerId,
            isPrimary: true,
          },
          data: {
            isPrimary: false,
          },
        });
      }

      const membership = await transaction.customerMembership.upsert({
        where: {
          customerId_userId: {
            customerId,
            userId: user.id,
          },
        },
        update: {
          status: 'ACTIVE',
          isPrimary: dto.isPrimary ?? false,
          invitedByUserId: auth.userId,
          joinedAt: new Date(),
          endedAt: null,
        },
        create: {
          customerId,
          userId: user.id,
          status: 'ACTIVE',
          isPrimary: dto.isPrimary ?? false,
          invitedByUserId: auth.userId,
          joinedAt: new Date(),
        },
      });

      const assignment = await transaction.roleAssignment.upsert({
        where: {
          userId_roleId_scopeType_scopeId: {
            userId: user.id,
            roleId: role.id,
            scopeType: 'CUSTOMER',
            scopeId: customerId,
          },
        },
        update: {
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
          scopeType: 'CUSTOMER',
          scopeId: customerId,
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
      action: 'customer.member.provisioned',
      resourceType: 'User',
      resourceId: result.user.id,
      scopeType: 'CUSTOMER',
      scopeId: customerId,
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

  private async resolveDealer(
    auth: AuthContext,
    requestedDealerId?: string,
  ): Promise<string | null> {
    if (this.context.isPlatformScoped(auth)) {
      if (!requestedDealerId) {
        return null;
      }

      await this.context.assertDealerExists(requestedDealerId);
      return requestedDealerId;
    }

    const dealerIds = this.context.dealerScopeIds(auth);

    if (requestedDealerId) {
      this.context.assertDealer(auth, requestedDealerId);
      await this.context.assertDealerExists(requestedDealerId);
      return requestedDealerId;
    }

    if (dealerIds.length !== 1) {
      throw new BadRequestException(
        'managingDealerId is required when more than one dealer scope is available.',
      );
    }

    await this.context.assertDealerExists(dealerIds[0]);
    return dealerIds[0];
  }

  private async resolveGroup(
    dealerId: string | null,
    requestedGroupId?: string,
  ): Promise<string | null> {
    if (!requestedGroupId) {
      return null;
    }

    if (!dealerId) {
      throw new BadRequestException('A direct customer cannot belong to a dealer customer group.');
    }

    const group = await this.prisma.customerGroup.findFirst({
      where: {
        id: requestedGroupId,
        dealerOrganizationId: dealerId,
        status: 'ACTIVE',
      },
      select: {
        id: true,
      },
    });

    if (!group) {
      throw new BadRequestException(
        'Customer group does not belong to the selected dealer or is not active.',
      );
    }

    return group.id;
  }

  private address(value?: AddressDto): Prisma.InputJsonValue | undefined {
    if (!value) {
      return undefined;
    }

    return {
      line1: value.line1 ?? '',
      line2: value.line2 ?? '',
      city: value.city ?? '',
      district: value.district ?? '',
      postalCode: value.postalCode ?? '',
      country: value.country ?? 'Bangladesh',
    };
  }
}
