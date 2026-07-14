import { ConflictException, Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../../database/prisma.service';
import { AuditService } from '../../identity/audit/audit.service';
import type { AuthContext } from '../../identity/common/auth-context';
import { ManagementCodeService } from '../common/management-code.service';
import { ManagementContextService } from '../common/management-context.service';
import type { CreateCustomerGroupDto } from './dto/create-customer-group.dto';
import type { UpdateCustomerGroupDto } from './dto/update-customer-group.dto';

@Injectable()
export class CustomerGroupsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly context: ManagementContextService,
    private readonly codes: ManagementCodeService,
    private readonly auditService: AuditService,
  ) {}

  async list(auth: AuthContext, dealerId: string) {
    this.context.assertDealer(auth, dealerId);
    await this.context.assertDealerExists(dealerId);

    return this.prisma.customerGroup.findMany({
      where: {
        dealerOrganizationId: dealerId,
      },
      orderBy: [
        {
          status: 'asc',
        },
        {
          name: 'asc',
        },
      ],
      include: {
        _count: {
          select: {
            customers: true,
          },
        },
      },
    });
  }

  async create(auth: AuthContext, dealerId: string, dto: CreateCustomerGroupDto) {
    this.context.assertDealer(auth, dealerId);
    await this.context.assertDealerExists(dealerId);

    const normalizedName = dto.name.trim().toLowerCase();

    const duplicate = await this.prisma.customerGroup.count({
      where: {
        dealerOrganizationId: dealerId,
        normalizedName,
      },
    });

    if (duplicate > 0) {
      throw new ConflictException('A customer group with this name already exists for the dealer.');
    }

    const group = await this.prisma.customerGroup.create({
      data: {
        code: this.codes.customerGroup(),
        dealerOrganizationId: dealerId,
        name: dto.name.trim(),
        normalizedName,
        description: dto.description?.trim(),
        status: 'ACTIVE',
        createdByUserId: auth.userId,
      },
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.context.actorOrganizationId(auth),
      action: 'customer_group.created',
      resourceType: 'CustomerGroup',
      resourceId: group.id,
      scopeType: 'CUSTOMER_GROUP',
      scopeId: group.id,
      afterData: group,
      metadata: {
        dealerId,
      },
    });

    return group;
  }

  async update(auth: AuthContext, dealerId: string, groupId: string, dto: UpdateCustomerGroupDto) {
    this.context.assertDealer(auth, dealerId);

    const before = await this.prisma.customerGroup.findFirst({
      where: {
        id: groupId,
        dealerOrganizationId: dealerId,
      },
    });

    if (!before) {
      throw new NotFoundException('Customer group was not found.');
    }

    const normalizedName = dto.name ? dto.name.trim().toLowerCase() : undefined;

    if (normalizedName && normalizedName !== before.normalizedName) {
      const duplicate = await this.prisma.customerGroup.count({
        where: {
          dealerOrganizationId: dealerId,
          normalizedName,
          id: {
            not: groupId,
          },
        },
      });

      if (duplicate > 0) {
        throw new ConflictException(
          'A customer group with this name already exists for the dealer.',
        );
      }
    }

    const updated = await this.prisma.customerGroup.update({
      where: {
        id: groupId,
      },
      data: {
        name: dto.name?.trim(),
        normalizedName,
        description: dto.description?.trim(),
        status: dto.status,
        archivedAt: dto.status === 'ARCHIVED' ? new Date() : dto.status ? null : undefined,
      },
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.context.actorOrganizationId(auth),
      action: 'customer_group.updated',
      resourceType: 'CustomerGroup',
      resourceId: groupId,
      scopeType: 'CUSTOMER_GROUP',
      scopeId: groupId,
      beforeData: before,
      afterData: updated,
      metadata: {
        dealerId,
      },
    });

    return updated;
  }
}
