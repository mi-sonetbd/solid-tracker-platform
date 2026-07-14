import { ApiPropertyOptional } from '@nestjs/swagger';
import { IsOptional, IsUUID } from 'class-validator';

export class SyncGeofenceDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  serverId?: string;
}
