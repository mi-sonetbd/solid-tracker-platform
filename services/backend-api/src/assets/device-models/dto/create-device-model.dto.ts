import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsIn, IsObject, IsOptional, IsString, MaxLength, MinLength } from 'class-validator';

const networkTypes = [
  'GSM_2G',
  'UMTS_3G',
  'LTE_4G',
  'LTE_5G',
  'LORA',
  'SATELLITE',
  'OTHER',
] as const;

export class CreateDeviceModelDto {
  @ApiProperty()
  @IsString()
  @MinLength(2)
  @MaxLength(120)
  manufacturer!: string;

  @ApiProperty()
  @IsString()
  @MinLength(2)
  @MaxLength(160)
  modelName!: string;

  @ApiProperty({ example: 'osmand' })
  @IsString()
  @MinLength(1)
  @MaxLength(100)
  protocol!: string;

  @ApiProperty({ enum: networkTypes })
  @IsIn(networkTypes)
  networkType!: (typeof networkTypes)[number];

  @ApiPropertyOptional({
    example: {
      ignition: true,
      relay: true,
      sos: true,
    },
  })
  @IsOptional()
  @IsObject()
  capabilities?: Record<string, unknown>;
}
