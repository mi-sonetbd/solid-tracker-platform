import { PartialType } from '@nestjs/swagger';
import { UpdateServicePlanDto } from './update-service-plan.dto';

export class CreatePlanVersionDto extends PartialType(UpdateServicePlanDto) {}
