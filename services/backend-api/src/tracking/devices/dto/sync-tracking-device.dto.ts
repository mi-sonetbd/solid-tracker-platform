import { ApiPropertyOptional } from '@nestjs/swagger';
import { IsBoolean, IsOptional, IsUUID } from 'class-validator';

export class SyncTrackingDeviceDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  serverId?: string;

  @ApiPropertyOptional({ default: false })
  @IsOptional()
  @IsBoolean()
  forceUpdate?: boolean;
}
