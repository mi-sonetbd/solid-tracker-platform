import { Type } from 'class-transformer';
import {
  IsArray,
  IsBoolean,
  IsInt,
  IsNumber,
  IsObject,
  IsOptional,
  IsString,
  Max,
  Min,
} from 'class-validator';

export class TraccarPositionWebhookDto {
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  id?: number;

  @Type(() => Number)
  @IsInt()
  deviceId!: number;

  @IsOptional()
  @IsString()
  protocol?: string;

  @IsOptional()
  @IsString()
  serverTime?: string;

  @IsOptional()
  @IsString()
  deviceTime?: string;

  @IsOptional()
  @IsString()
  fixTime?: string;

  @IsBoolean()
  valid!: boolean;

  @Type(() => Number)
  @IsNumber()
  @Min(-90)
  @Max(90)
  latitude!: number;

  @Type(() => Number)
  @IsNumber()
  @Min(-180)
  @Max(180)
  longitude!: number;

  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  altitude?: number;

  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  speed?: number;

  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  course?: number;

  @IsOptional()
  @IsString()
  address?: string;

  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  accuracy?: number;

  @IsOptional()
  @IsObject()
  network?: Record<string, unknown>;

  @IsOptional()
  @IsArray()
  geofenceIds?: number[];

  @IsOptional()
  @IsObject()
  attributes?: Record<string, unknown>;
}
