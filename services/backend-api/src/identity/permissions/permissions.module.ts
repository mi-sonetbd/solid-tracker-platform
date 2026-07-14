import { Module } from '@nestjs/common';
import { AccessControlModule } from '../access-control/access-control.module';
import { PermissionsController } from './permissions.controller';

@Module({
  imports: [AccessControlModule],
  controllers: [PermissionsController],
})
export class PermissionsModule {}
