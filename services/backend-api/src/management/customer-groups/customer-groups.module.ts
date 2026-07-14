import { Module } from '@nestjs/common';
import { AccessControlModule } from '../../identity/access-control/access-control.module';
import { AuditModule } from '../../identity/audit/audit.module';
import { ManagementCodeService } from '../common/management-code.service';
import { ManagementContextService } from '../common/management-context.service';
import { CustomerGroupsController } from './customer-groups.controller';
import { CustomerGroupsService } from './customer-groups.service';

@Module({
  imports: [AccessControlModule, AuditModule],
  controllers: [CustomerGroupsController],
  providers: [CustomerGroupsService, ManagementContextService, ManagementCodeService],
  exports: [CustomerGroupsService],
})
export class CustomerGroupsModule {}
