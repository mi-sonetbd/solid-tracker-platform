import { Module } from '@nestjs/common';
import { AccessControlModule } from '../access-control/access-control.module';
import { AuditModule } from '../audit/audit.module';
import { SessionsController } from './sessions.controller';
import { SessionsService } from './sessions.service';

@Module({
  imports: [AccessControlModule, AuditModule],
  controllers: [SessionsController],
  providers: [SessionsService],
})
export class SessionsModule {}
