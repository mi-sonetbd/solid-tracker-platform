import { Module } from '@nestjs/common';
import { AccessControlModule } from '../../identity/access-control/access-control.module';
import { AuditModule } from '../../identity/audit/audit.module';
import { AssetAccessService } from '../common/asset-access.service';
import { AssetCodeService } from '../common/asset-code.service';
import { VehiclesController } from './vehicles.controller';
import { VehiclesService } from './vehicles.service';

@Module({
  imports: [AccessControlModule, AuditModule],
  controllers: [VehiclesController],
  providers: [VehiclesService, AssetAccessService, AssetCodeService],
  exports: [VehiclesService],
})
export class VehiclesModule {}
