import { Module } from '@nestjs/common';
import { AccessControlModule } from '../identity/access-control/access-control.module';
import { TrackingApiModule } from '../tracking/tracking-api.module';
import { MobileBillingController } from './billing/mobile-billing.controller';
import { MobileBillingService } from './billing/mobile-billing.service';
import { MobileAccessService } from './common/mobile-access.service';
import { MobileCacheService } from './common/mobile-cache.service';
import { MobileDashboardService } from './dashboard/mobile-dashboard.service';
import { MobileLiveSessionController } from './live/mobile-live-session.controller';
import { MobileLiveSessionService } from './live/mobile-live-session.service';
import { MobileNotificationsController } from './notifications/mobile-notifications.controller';
import { MobileNotificationsService } from './notifications/mobile-notifications.service';
import { MobileProfileController } from './profile/mobile-profile.controller';
import { MobileProfileService } from './profile/mobile-profile.service';
import { MobileTripBuilderService } from './vehicles/mobile-trip-builder.service';
import { MobileVehiclesController } from './vehicles/mobile-vehicles.controller';
import { MobileVehiclesService } from './vehicles/mobile-vehicles.service';

@Module({
  imports: [AccessControlModule, TrackingApiModule],
  controllers: [
    MobileProfileController,
    MobileVehiclesController,
    MobileBillingController,
    MobileNotificationsController,
    MobileLiveSessionController,
  ],
  providers: [
    MobileAccessService,
    MobileCacheService,
    MobileProfileService,
    MobileDashboardService,
    MobileTripBuilderService,
    MobileVehiclesService,
    MobileBillingService,
    MobileNotificationsService,
    MobileLiveSessionService,
  ],
})
export class MobileApiModule {}
