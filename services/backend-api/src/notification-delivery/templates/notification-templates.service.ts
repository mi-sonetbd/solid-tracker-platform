import { Injectable, NotFoundException } from '@nestjs/common';
import type { NotificationChannel, Prisma } from '../../generated/prisma/client';
import { PrismaService } from '../../database/prisma.service';
import { AuditService } from '../../identity/audit/audit.service';
import type { AuthContext } from '../../identity/common/auth-context';
import { NotificationDeliveryAccessService } from '../common/notification-access.service';
import { NotificationCodeService } from '../common/notification-code.service';
import { NotificationTemplateRendererService } from '../common/notification-template-renderer.service';
import type { CreateNotificationTemplateDto } from '../dto/create-notification-template.dto';
import type { NotificationTemplateQueryDto } from '../dto/notification-template-query.dto';

@Injectable()
export class NotificationTemplatesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly access: NotificationDeliveryAccessService,
    private readonly codes: NotificationCodeService,
    private readonly renderer: NotificationTemplateRendererService,
    private readonly audit: AuditService,
  ) {}

  async list(auth: AuthContext, query: NotificationTemplateQueryDto) {
    this.access.assertPlatform(auth);
    const skip = (query.page - 1) * query.pageSize;
    const where: Prisma.NotificationTemplateWhereInput = {
      channel: query.channel as NotificationChannel | undefined,
      status: query.status as 'DRAFT' | 'ACTIVE' | 'INACTIVE' | 'ARCHIVED' | undefined,
      OR: query.search
        ? [
            {
              templateKey: {
                contains: query.search,
                mode: 'insensitive',
              },
            },
            {
              name: {
                contains: query.search,
                mode: 'insensitive',
              },
            },
          ]
        : undefined,
    };
    const [items, total] = await Promise.all([
      this.prisma.notificationTemplate.findMany({
        where,
        skip,
        take: query.pageSize,
        orderBy: [
          { templateKey: 'asc' },
          { channel: 'asc' },
          { locale: 'asc' },
          { version: 'desc' },
        ],
      }),
      this.prisma.notificationTemplate.count({ where }),
    ]);

    return {
      items,
      page: query.page,
      pageSize: query.pageSize,
      total,
      totalPages: Math.ceil(total / query.pageSize),
    };
  }

  async createVersion(auth: AuthContext, dto: CreateNotificationTemplateDto) {
    this.access.assertPlatform(auth);
    const templateKey = dto.templateKey.trim().toLowerCase();
    const locale = (dto.locale ?? 'en').trim().toLowerCase();
    const versionAggregate = await this.prisma.notificationTemplate.aggregate({
      where: {
        templateKey,
        channel: dto.channel,
        locale,
      },
      _max: { version: true },
    });
    const version = (versionAggregate._max.version ?? 0) + 1;

    const template = await this.prisma.$transaction(async (transaction) => {
      if (dto.activate) {
        await transaction.notificationTemplate.updateMany({
          where: {
            templateKey,
            channel: dto.channel,
            locale,
            status: 'ACTIVE',
          },
          data: { status: 'INACTIVE' },
        });
      }

      return transaction.notificationTemplate.create({
        data: {
          templateCode: this.codes.template(),
          templateKey,
          channel: dto.channel,
          locale,
          version,
          name: dto.name.trim(),
          subjectTemplate: dto.subjectTemplate?.trim() || null,
          bodyTemplate: dto.bodyTemplate,
          variableSchema: dto.variableSchema
            ? (JSON.parse(JSON.stringify(dto.variableSchema)) as Prisma.InputJsonValue)
            : undefined,
          status: dto.activate ? 'ACTIVE' : 'DRAFT',
          createdByUserId: auth.userId,
          activatedAt: dto.activate ? new Date() : null,
        },
      });
    });

    await this.audit.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'notification.template.version-created',
      resourceType: 'NotificationTemplate',
      resourceId: template.id,
      metadata: {
        templateKey,
        channel: dto.channel,
        locale,
        version,
        status: template.status,
      },
    });

    return template;
  }

  async activate(auth: AuthContext, templateId: string) {
    this.access.assertPlatform(auth);
    const template = await this.prisma.notificationTemplate.findUnique({
      where: { id: templateId },
    });

    if (!template) {
      throw new NotFoundException('Notification template was not found.');
    }

    const activated = await this.prisma.$transaction(async (transaction) => {
      await transaction.notificationTemplate.updateMany({
        where: {
          templateKey: template.templateKey,
          channel: template.channel,
          locale: template.locale,
          status: 'ACTIVE',
          id: { not: template.id },
        },
        data: { status: 'INACTIVE' },
      });

      return transaction.notificationTemplate.update({
        where: { id: template.id },
        data: {
          status: 'ACTIVE',
          activatedAt: new Date(),
          archivedAt: null,
        },
      });
    });

    await this.audit.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'notification.template.activated',
      resourceType: 'NotificationTemplate',
      resourceId: activated.id,
      metadata: {
        templateKey: activated.templateKey,
        version: activated.version,
      },
    });

    return activated;
  }

  async archive(auth: AuthContext, templateId: string) {
    this.access.assertPlatform(auth);
    const existing = await this.prisma.notificationTemplate.findUnique({
      where: { id: templateId },
    });

    if (!existing) {
      throw new NotFoundException('Notification template was not found.');
    }

    const archived = await this.prisma.notificationTemplate.update({
      where: { id: templateId },
      data: {
        status: 'ARCHIVED',
        archivedAt: new Date(),
      },
    });

    await this.audit.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'notification.template.archived',
      resourceType: 'NotificationTemplate',
      resourceId: archived.id,
    });

    return archived;
  }

  async preview(auth: AuthContext, templateId: string, variables: Record<string, unknown>) {
    this.access.assertPlatform(auth);
    const template = await this.prisma.notificationTemplate.findUnique({
      where: { id: templateId },
    });

    if (!template) {
      throw new NotFoundException('Notification template was not found.');
    }

    return {
      templateId: template.id,
      subject: template.subjectTemplate
        ? this.renderer.render(template.subjectTemplate, variables)
        : null,
      content: this.renderer.render(template.bodyTemplate, variables),
      referencedVariables: this.renderer.referencedVariables(
        `${template.subjectTemplate ?? ''}\n${template.bodyTemplate}`,
      ),
    };
  }

  async renderActive(input: {
    templateKey: string;
    channel: NotificationChannel;
    locale: string;
    variables: Record<string, unknown>;
  }): Promise<{
    templateId: string;
    subject: string | null;
    content: string;
  }> {
    const template = await this.prisma.notificationTemplate.findFirst({
      where: {
        templateKey: input.templateKey.trim().toLowerCase(),
        channel: input.channel,
        locale: input.locale.trim().toLowerCase(),
        status: 'ACTIVE',
      },
      orderBy: { version: 'desc' },
    });

    if (!template) {
      throw new NotFoundException('An active notification template was not found.');
    }

    return {
      templateId: template.id,
      subject: template.subjectTemplate
        ? this.renderer.render(template.subjectTemplate, input.variables)
        : null,
      content: this.renderer.render(template.bodyTemplate, input.variables),
    };
  }
}
