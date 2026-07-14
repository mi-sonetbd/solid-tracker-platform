import { Module } from '@nestjs/common';
import { AccessControlModule } from '../access-control/access-control.module';
import { RolesController } from './roles.controller';
import { RolesService } from './roles.service';

@Module({
  imports: [AccessControlModule],
  controllers: [RolesController],
  providers: [RolesService],
})
export class RolesModule {}
