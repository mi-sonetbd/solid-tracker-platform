import { Injectable } from '@nestjs/common';
import type { NotificationChannel } from '../../generated/prisma/client';
import type {
  NotificationProviderAdapter,
  NotificationSendInput,
  NotificationSendResult,
} from '../common/notification-delivery.types';

@Injectable()
export class SandboxNotificationAdapter implements NotificationProviderAdapter {
  readonly provider = 'SANDBOX';

  supports(channel: NotificationChannel): boolean {
    void channel;
    return true;
  }

  async send(input: NotificationSendInput): Promise<NotificationSendResult> {
    if (input.recipient.toLowerCase().includes('force-fail')) {
      throw new Error('Sandbox provider was instructed to fail.');
    }

    return {
      provider: this.provider,
      providerMessageId: `sandbox-${input.idempotencyKey}`,
      status: input.channel === 'IN_APP' ? 'DELIVERED' : 'SENT',
      responsePayload: {
        accepted: true,
        channel: input.channel,
      },
    };
  }
}
