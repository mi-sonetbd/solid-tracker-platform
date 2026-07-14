import { Module } from '@nestjs/common';
import { AccessControlModule } from '../../identity/access-control/access-control.module';
import { AuditModule } from '../../identity/audit/audit.module';
import { ManagementCodeService } from '../common/management-code.service';
import { ManagementContextService } from '../common/management-context.service';
import { DealersController } from './dealers.controller';
import { DealersService } from './dealers.service';

@Module({
  imports: [AccessControlModule, AuditModule],
  controllers: [DealersController],
  providers: [DealersService, ManagementContextService, ManagementCodeService],
  exports: [DealersService],
})
export class DealersModule {}
