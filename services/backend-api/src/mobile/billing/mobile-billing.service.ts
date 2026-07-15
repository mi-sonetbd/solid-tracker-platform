import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../database/prisma.service';
import type { AuthContext } from '../../identity/common/auth-context';
import { MobileAccessService } from '../common/mobile-access.service';
import { mobileJsonSafe } from '../common/mobile-json.util';
import type { MobileCursorQueryDto } from '../common/mobile-query.dto';

@Injectable()
export class MobileBillingService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly access: MobileAccessService,
  ) {}

  async subscriptions(auth: AuthContext, query: MobileCursorQueryDto) {
    const customerIds = this.access.customerIds(auth);
    const items = await this.prisma.subscription.findMany({
      where: {
        customerId: {
          in: customerIds,
        },
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
      include: {
        vehicle: {
          select: {
            id: true,
            vehicleCode: true,
            registrationNumber: true,
            vehicleType: true,
          },
        },
        servicePlan: true,
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

  async invoices(auth: AuthContext, query: MobileCursorQueryDto) {
    const customerIds = this.access.customerIds(auth);
    const items = await this.prisma.invoice.findMany({
      where: {
        customerId: {
          in: customerIds,
        },
      },
      orderBy: [
        {
          issueDate: 'desc',
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
      include: {
        subscription: {
          include: {
            vehicle: {
              select: {
                id: true,
                vehicleCode: true,
                registrationNumber: true,
              },
            },
            servicePlan: {
              select: {
                name: true,
              },
            },
          },
        },
        lines: {
          orderBy: {
            lineNumber: 'asc',
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
