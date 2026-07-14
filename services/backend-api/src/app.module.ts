import { Module } from '@nestjs/common';
import { TrackingApiModule } from './tracking/tracking-api.module';
import { BillingApiModule } from './billing/billing-api.module';
import { AssetManagementModule } from './assets/asset-management.module';
import { ConfigModule } from '@nestjs/config';
import { AppController } from './app.controller';
import { AppService } from './app.service';
import { environmentValidationSchema } from './config/environment.validation';
import { DatabaseModule } from './database/database.module';
import { HealthModule } from './health/health.module';
import { IdentityAccessModule } from './identity/identity-access.module';
import { DealerCustomerManagementModule } from './management/dealer-customer-management.module';
import { RedisModule } from './redis/redis.module';

@Module({
  imports: [
    TrackingApiModule,
    BillingApiModule,
    AssetManagementModule,
    ConfigModule.forRoot({
      isGlobal: true,
      cache: true,
      envFilePath: ['../../.env', '.env'],
      validationSchema: environmentValidationSchema,
      validationOptions: {
        abortEarly: false,
      },
    }),
    DatabaseModule,
    RedisModule,
    IdentityAccessModule,
    DealerCustomerManagementModule,
    HealthModule,
  ],
  controllers: [AppController],
  providers: [AppService],
})
export class AppModule {}
