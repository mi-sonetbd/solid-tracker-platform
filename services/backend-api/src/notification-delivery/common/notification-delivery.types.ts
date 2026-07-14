import type { NotificationChannel, Prisma } from '../../generated/prisma/client';

export interface NotificationSendInput {
  notificationId: string;
  idempotencyKey: string;
  channel: NotificationChannel;
  recipient: string;
  subject?: string | null;
  content: string;
  callbackUrl: string;
}

export interface NotificationSendResult {
  provider: string;
  providerMessageId: string;
  status: 'SENT' | 'DELIVERED';
  responsePayload?: Prisma.InputJsonValue;
}

export interface NotificationProviderAdapter {
  provider: string;
  supports(channel: NotificationChannel): boolean;
  send(input: NotificationSendInput): Promise<NotificationSendResult>;
}
