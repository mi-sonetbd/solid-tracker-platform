import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import {
  ArrayMaxSize,
  ArrayMinSize,
  IsArray,
  IsIn,
  IsOptional,
  IsString,
  IsUUID,
  MaxLength,
} from 'class-validator';

const transferTargetTypes = ['DEALER', 'CUSTOMER'] as const;

export class TransferDevicesDto {
  @ApiProperty({
    type: String,
    isArray: true,
  })
  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(100)
  @IsUUID('4', { each: true })
  deviceIds!: string[];

  @ApiProperty({ enum: transferTargetTypes })
  @IsIn(transferTargetTypes)
  targetType!: (typeof transferTargetTypes)[number];

  @ApiProperty()
  @IsUUID()
  targetId!: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(1000)
  notes?: string;
}
