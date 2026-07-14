import { ApiProperty } from '@nestjs/swagger';
import { IsIn } from 'class-validator';

const verificationStatuses = ['VERIFIED', 'REJECTED'] as const;

export class VerifyPayoutAccountDto {
  @ApiProperty({ enum: verificationStatuses })
  @IsIn(verificationStatuses)
  verificationStatus!: (typeof verificationStatuses)[number];
}
