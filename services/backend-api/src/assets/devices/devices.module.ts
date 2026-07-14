import { Module } from '@nestjs/common';
import { AccessControlModule } from '../../identity/access-control/access-control.module';
import { AuditModule } from '../../identity/audit/audit.module';
import { AssetAccessService } from '../common/asset-access.service';
import { AssetCodeService } from '../common/asset-code.service';
import { DevicesController } from './devices.controller';
import { DevicesService } from './devices.service';

@Module({
  imports: [AccessControlModule, AuditModule],
  controllers: [DevicesController],
  providers: [DevicesService, AssetAccessService, AssetCodeService],
})
export class DevicesModule {}
