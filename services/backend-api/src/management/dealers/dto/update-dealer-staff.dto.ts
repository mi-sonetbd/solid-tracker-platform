import { ApiProperty } from '@nestjs/swagger';
import { IsBoolean } from 'class-validator';

export class UpdateDealerStaffDto {
  @ApiProperty()
  @IsBoolean()
  active!: boolean;
}
