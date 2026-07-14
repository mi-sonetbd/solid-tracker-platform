import { Module } from '@nestjs/common';
import { AccessControlModule } from '../identity/access-control/access-control.module';
import { AuditModule } from '../identity/audit/audit.module';
import { NotificationProviderRegistryService } from './adapters/notification-provider-registry.service';
import { SandboxNotificationAdapter } from './adapters/sandbox-notification.adapter';
import { SignedNotificationProxyAdapter } from './adapters/signed-notification-proxy.adapter';
import { NotificationDeliveryAccessService } from './common/notification-access.service';
import { NotificationCodeService } from './common/notification-code.service';
import { NotificationRateLimiterService } from './common/notification-rate-limiter.service';
import { NotificationSignatureService } from './common/notification-signature.service';
import { NotificationTemplateRendererService } from './common/notification-template-renderer.service';
import { NotificationDeliveryController } from './delivery/notification-delivery.controller';
import { NotificationDeliveryService } from './delivery/notification-delivery.service';
import { NotificationDeliveryWorkerService } from './delivery/notification-delivery-worker.service';
import { NotificationProviderCallbackController } from './delivery/notification-provider-callback.controller';
import { NotificationTemplatesController } from './templates/notification-templates.controller';
import { NotificationTemplatesService } from './templates/notification-templates.service';

@Module({
  imports: [AccessControlModule, AuditModule],
  controllers: [
    NotificationTemplatesController,
    NotificationDeliveryController,
    NotificationProviderCallbackController,
  ],
  providers: [
    NotificationDeliveryAccessService,
    NotificationCodeService,
    NotificationSignatureService,
    NotificationTemplateRendererService,
    NotificationRateLimiterService,
    SandboxNotificationAdapter,
    SignedNotificationProxyAdapter,
    NotificationProviderRegistryService,
    NotificationTemplatesService,
    NotificationDeliveryWorkerService,
    NotificationDeliveryService,
  ],
  exports: [
    NotificationSignatureService,
    NotificationTemplatesService,
    NotificationDeliveryWorkerService,
  ],
})
export class NotificationDeliveryModule {}
