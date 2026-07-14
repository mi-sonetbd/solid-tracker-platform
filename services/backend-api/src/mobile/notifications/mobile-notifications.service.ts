import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../database/prisma.service';
import type { AuthContext } from '../../identity/common/auth-context';
import { MobileAccessService } from '../common/mobile-access.service';
import { mobileJsonSafe } from '../common/mobile-json.util';
import type { MobileCursorQueryDto } from '../common/mobile-query.dto';

@Injectable()
export class MobileNotificationsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly access: MobileAccessService,
  ) {}

  async list(auth: AuthContext, query: MobileCursorQueryDto) {
    const customerIds = this.access.customerIds(auth);
    const items = await this.prisma.notification.findMany({
      where: {
        customerId: {
          in: customerIds,
        },
        OR: [
          {
            userId: null,
          },
          {
            userId: auth.userId,
          },
        ],
      },
      orderBy: [
        {
          createdAt: 'desc',
        },
        {
          id: 'desc',
        },
      ],
      cursor: query.cursor
        ? {
            id: query.cursor,
          }
        : undefined,
      skip: query.cursor ? 1 : 0,
      take: query.limit + 1,
      select: {
        id: true,
        notificationCode: true,
        channel: true,
        recipient: true,
        subject: true,
        renderedContent: true,
        status: true,
        provider: true,
        queuedAt: true,
        sentAt: true,
        deliveredAt: true,
        failedAt: true,
        failureReason: true,
        createdAt: true,
        trackingEvent: {
          select: {
            id: true,
            eventType: true,
            severity: true,
            vehicleId: true,
            latitude: true,
            longitude: true,
            occurredAt: true,
          },
        },
      },
    });
    const hasMore = items.length > query.limit;

    if (hasMore) {
      items.pop();
    }

    return mobileJsonSafe({
      data: items,
      meta: {
        limit: query.limit,
        count: items.length,
        nextCursor: hasMore && items.length > 0 ? items[items.length - 1].id : null,
      },
    });
  }
}
