import { Module } from '@nestjs/common';
import { AccessControlModule } from '../../identity/access-control/access-control.module';
import { AuditModule } from '../../identity/audit/audit.module';
import { ManagementCodeService } from '../common/management-code.service';
import { ManagementContextService } from '../common/management-context.service';
import { CustomersController } from './customers.controller';
import { CustomersService } from './customers.service';

@Module({
  imports: [AccessControlModule, AuditModule],
  controllers: [CustomersController],
  providers: [CustomersService, ManagementContextService, ManagementCodeService],
  exports: [CustomersService],
})
export class CustomersModule {}
