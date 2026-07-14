import { Module } from '@nestjs/common';
import { SecurityModule } from '../common/security.module';
import { AccessControlService } from './access-control.service';
import { AccessTokenGuard } from './access-token.guard';
import { PermissionsGuard } from './permissions.guard';

@Module({
  imports: [SecurityModule],
  providers: [AccessControlService, AccessTokenGuard, PermissionsGuard],
  exports: [SecurityModule, AccessControlService, AccessTokenGuard, PermissionsGuard],
})
export class AccessControlModule {}
