import { Module } from '@nestjs/common';
import { AccessControlModule } from '../../identity/access-control/access-control.module';
import { AuditModule } from '../../identity/audit/audit.module';
import { AssetAccessService } from '../common/asset-access.service';
import { AssetCodeService } from '../common/asset-code.service';
import { DeviceModelsController } from './device-models.controller';
import { DeviceModelsService } from './device-models.service';

@Module({
  imports: [AccessControlModule, AuditModule],
  controllers: [DeviceModelsController],
  providers: [DeviceModelsService, AssetAccessService, AssetCodeService],
})
export class DeviceModelsModule {}
