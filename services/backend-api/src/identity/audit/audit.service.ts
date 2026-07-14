import { Injectable } from '@nestjs/common';
import type { Prisma } from '../../generated/prisma/client';
import { PrismaService } from '../../database/prisma.service';

type AuditScopeType =
  'PLATFORM' | 'ZONE' | 'DEALER' | 'CUSTOMER_GROUP' | 'CUSTOMER' | 'VEHICLE' | 'SELF';

export interface AuditRecordInput {
  actorUserId?: string;
  actorOrganizationId?: string;
  action: string;
  resourceType: string;
  resourceId?: string;
  scopeType?: AuditScopeType;
  scopeId?: string;
  beforeData?: unknown;
  afterData?: unknown;
  metadata?: unknown;
  ipAddress?: string;
  userAgent?: string;
  correlationId?: string;
}

@Injectable()
export class AuditService {
  constructor(private readonly prisma: PrismaService) {}

  async record(input: AuditRecordInput): Promise<void> {
    await this.prisma.auditLog.create({
      data: {
        actorUserId: input.actorUserId,
        actorOrganizationId: input.actorOrganizationId,
        action: input.action,
        resourceType: input.resourceType,
        resourceId: input.resourceId,
        scopeType: input.scopeType,
        scopeId: input.scopeId,
        beforeData: this.toJson(input.beforeData),
        afterData: this.toJson(input.afterData),
        metadata: this.toJson(input.metadata),
        ipAddress: input.ipAddress,
        userAgent: input.userAgent,
        correlationId: input.correlationId,
      },
    });
  }

  private toJson(value: unknown): Prisma.InputJsonValue | undefined {
    if (value === undefined) {
      return undefined;
    }

    return JSON.parse(JSON.stringify(value)) as Prisma.InputJsonValue;
  }
}
