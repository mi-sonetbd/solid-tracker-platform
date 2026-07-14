import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../database/prisma.service';
import type { AuthContext } from '../../identity/common/auth-context';
import { BillingAccessService } from '../../billing/common/billing-access.service';
import type { ReconcilePaymentsDto } from '../dto/reconcile-payments.dto';
import { GatewayPaymentService } from './gateway-payment.service';

@Injectable()
export class PaymentReconciliationService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly access: BillingAccessService,
    private readonly gateways: GatewayPaymentService,
  ) {}

  async batch(auth: AuthContext, dto: ReconcilePaymentsDto) {
    this.access.assertPlatform(auth);

    const cutoff = new Date(Date.now() - dto.minimumAgeMinutes * 60 * 1000);
    const payments = await this.prisma.payment.findMany({
      where: {
        paymentGateway: {
          in: ['OTHER', 'BKASH', 'NAGAD', 'SSLCOMMERZ'],
        },
        status: {
          in: ['INITIATED', 'PENDING'],
        },
        initiatedAt: {
          lte: cutoff,
        },
      },
      orderBy: {
        initiatedAt: 'asc',
      },
      take: dto.limit,
      select: {
        id: true,
      },
    });

    const results: Array<Record<string, unknown>> = [];

    for (const payment of payments) {
      try {
        results.push({
          paymentId: payment.id,
          status: 'SUCCEEDED',
          result: await this.gateways.reconcile(auth, payment.id),
        });
      } catch (error) {
        results.push({
          paymentId: payment.id,
          status: 'FAILED',
          error: error instanceof Error ? error.message : 'Unknown reconciliation error.',
        });
      }
    }

    return {
      attempted: results.length,
      succeeded: results.filter((result) => result.status === 'SUCCEEDED').length,
      failed: results.filter((result) => result.status === 'FAILED').length,
      results,
    };
  }
}
