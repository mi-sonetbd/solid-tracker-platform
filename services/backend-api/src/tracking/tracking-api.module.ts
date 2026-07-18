import { Module } from '@nestjs/common';
import { AccessControlModule } from '../identity/access-control/access-control.module';
import { AuditModule } from '../identity/audit/audit.module';
import { DeviceCommandsController } from './commands/device-commands.controller';
import { DeviceCommandsService } from './commands/device-commands.service';
import { TrackingAccessService } from './common/tracking-access.service';
import { TrackingCodeService } from './common/tracking-code.service';
import { TrackingCredentialCryptoService } from './common/tracking-credential-crypto.service';
import { TraccarClientService } from './common/traccar-client.service';
import { DeviceTrackingController } from './devices/device-tracking.controller';
import { DeviceTrackingService } from './devices/device-tracking.service';
import {
  TrackingEventsController,
  TrackingWebhooksController,
} from './events/tracking-events.controller';
import { TrackingEventsService } from './events/tracking-events.service';
import { TrackingWebhookGuard } from './events/tracking-webhook.guard';
import { GeofencesController } from './geofences/geofences.controller';
import { GeofencesService } from './geofences/geofences.service';
import { IntegrationJobsController } from './jobs/integration-jobs.controller';
import { IntegrationJobsService } from './jobs/integration-jobs.service';
import {
  NotificationRulesController,
  NotificationsController,
} from './notifications/notifications.controller';
import { NotificationsService } from './notifications/notifications.service';
import { TrackingPositionsController } from './positions/tracking-positions.controller';
import { TrackingPositionsService } from './positions/tracking-positions.service';
import { TraccarServersController } from './servers/traccar-servers.controller';
import { TraccarServersService } from './servers/traccar-servers.service';

@Module({
  imports: [AccessControlModule, AuditModule],
  controllers: [
    TraccarServersController,
    DeviceTrackingController,
    TrackingPositionsController,
    TrackingEventsController,
    TrackingWebhooksController,
    GeofencesController,
    NotificationRulesController,
    NotificationsController,
    DeviceCommandsController,
    IntegrationJobsController,
  ],
  providers: [
    TrackingAccessService,
    TrackingCodeService,
    TrackingCredentialCryptoService,
    TraccarClientService,
    TraccarServersService,
    IntegrationJobsService,
    DeviceTrackingService,
    TrackingPositionsService,
    NotificationsService,
    TrackingEventsService,
    GeofencesService,
    DeviceCommandsService,
    TrackingWebhookGuard,
  ],
  exports: [DeviceTrackingService, TrackingAccessService, TrackingPositionsService],
})
export class TrackingApiModule {}
