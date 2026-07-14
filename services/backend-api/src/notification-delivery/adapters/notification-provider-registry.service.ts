import { Injectable } from '@nestjs/common';
import type { NotificationChannel } from '../../generated/prisma/client';
import { SandboxNotificationAdapter } from './sandbox-notification.adapter';
import { SignedNotificationProxyAdapter } from './signed-notification-proxy.adapter';
import type {
  NotificationSendInput,
  NotificationSendResult,
} from '../common/notification-delivery.types';

@Injectable()
export class NotificationProviderRegistryService {
  constructor(
    private readonly sandbox: SandboxNotificationAdapter,
    private readonly proxy: SignedNotificationProxyAdapter,
  ) {}

  providerFor(channel: NotificationChannel): string {
    return this.proxy.isConfigured(channel)
      ? this.proxy.providerFor(channel)
      : this.sandbox.provider;
  }

  async send(input: NotificationSendInput): Promise<NotificationSendResult> {
    return this.proxy.isConfigured(input.channel)
      ? this.proxy.send(input)
      : this.sandbox.send(input);
  }

  callbackSecret(provider: string): string {
    return this.proxy.secretForProvider(provider);
  }
}
