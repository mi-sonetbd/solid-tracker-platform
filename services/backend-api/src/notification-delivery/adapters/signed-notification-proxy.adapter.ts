import { BadGatewayException, Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { NotificationChannel, Prisma } from '../../generated/prisma/client';
import { NotificationSignatureService } from '../common/notification-signature.service';
import type {
  NotificationSendInput,
  NotificationSendResult,
} from '../common/notification-delivery.types';

interface ProxyConfiguration {
  provider: string;
  url: string;
  secret: string;
}

@Injectable()
export class SignedNotificationProxyAdapter {
  private readonly timeoutMilliseconds: number;

  constructor(
    private readonly config: ConfigService,
    private readonly signatures: NotificationSignatureService,
  ) {
    this.timeoutMilliseconds = Number(
      this.config.get('NOTIFICATION_PROVIDER_HTTP_TIMEOUT_MS', 10000),
    );
  }

  isConfigured(channel: NotificationChannel): boolean {
    const configuration = this.configuration(channel);

    return configuration.url.length > 0 && configuration.secret.length >= 32;
  }

  providerFor(channel: NotificationChannel): string {
    return this.configuration(channel).provider;
  }

  async send(input: NotificationSendInput): Promise<NotificationSendResult> {
    const configuration = this.configuration(input.channel);

    if (!configuration.url || configuration.secret.length < 32) {
      throw new BadGatewayException(
        `Notification provider ${configuration.provider} is not configured.`,
      );
    }

    const timestamp = Date.now().toString();
    const eventId = input.idempotencyKey;
    const payload = {
      notificationId: input.notificationId,
      idempotencyKey: input.idempotencyKey,
      channel: input.channel,
      recipient: input.recipient,
      subject: input.subject,
      content: input.content,
      callbackUrl: input.callbackUrl,
    };
    const signature = this.signatures.sign(configuration.secret, timestamp, eventId, payload);
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.timeoutMilliseconds);

    try {
      const response = await fetch(configuration.url, {
        method: 'POST',
        headers: {
          'content-type': 'application/json',
          'x-solid-timestamp': timestamp,
          'x-solid-event-id': eventId,
          'x-solid-signature': signature,
        },
        body: JSON.stringify(payload),
        signal: controller.signal,
      });
      const responseText = await response.text();
      let responseBody: Record<string, unknown> = {};

      if (responseText) {
        try {
          responseBody = JSON.parse(responseText) as Record<string, unknown>;
        } catch {
          responseBody = { raw: responseText };
        }
      }

      if (!response.ok) {
        throw new BadGatewayException(
          `${configuration.provider} returned HTTP ${response.status}.`,
        );
      }

      const providerMessageId =
        typeof responseBody.providerMessageId === 'string'
          ? responseBody.providerMessageId
          : typeof responseBody.messageId === 'string'
            ? responseBody.messageId
            : undefined;

      if (!providerMessageId) {
        throw new BadGatewayException(
          `${configuration.provider} did not return a provider message ID.`,
        );
      }

      return {
        provider: configuration.provider,
        providerMessageId,
        status: responseBody.status === 'DELIVERED' ? 'DELIVERED' : 'SENT',
        responsePayload: JSON.parse(JSON.stringify(responseBody)) as Prisma.InputJsonValue,
      };
    } finally {
      clearTimeout(timer);
    }
  }

  secretForProvider(provider: string): string {
    const normalized = provider.toUpperCase();

    if (normalized === 'SANDBOX') {
      return this.config.getOrThrow<string>('NOTIFICATION_SANDBOX_WEBHOOK_SECRET');
    }

    if (normalized === 'SMS_PROXY') {
      return this.config.get<string>('NOTIFICATION_SMS_PROXY_SECRET', '');
    }

    if (normalized === 'EMAIL_PROXY') {
      return this.config.get<string>('NOTIFICATION_EMAIL_PROXY_SECRET', '');
    }

    if (normalized === 'PUSH_PROXY') {
      return this.config.get<string>('NOTIFICATION_PUSH_PROXY_SECRET', '');
    }

    throw new BadGatewayException(`Unsupported notification provider: ${provider}.`);
  }

  private configuration(channel: NotificationChannel): ProxyConfiguration {
    if (channel === 'SMS' || channel === 'WHATSAPP' || channel === 'VOICE_CALL') {
      return {
        provider: 'SMS_PROXY',
        url: this.config.get<string>('NOTIFICATION_SMS_PROXY_URL', ''),
        secret: this.config.get<string>('NOTIFICATION_SMS_PROXY_SECRET', ''),
      };
    }

    if (channel === 'EMAIL') {
      return {
        provider: 'EMAIL_PROXY',
        url: this.config.get<string>('NOTIFICATION_EMAIL_PROXY_URL', ''),
        secret: this.config.get<string>('NOTIFICATION_EMAIL_PROXY_SECRET', ''),
      };
    }

    return {
      provider: 'PUSH_PROXY',
      url: this.config.get<string>('NOTIFICATION_PUSH_PROXY_URL', ''),
      secret: this.config.get<string>('NOTIFICATION_PUSH_PROXY_SECRET', ''),
    };
  }
}
