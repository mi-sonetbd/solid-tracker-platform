import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { AccessControlModule } from '../identity/access-control/access-control.module';
import { AuditModule } from '../identity/audit/audit.module';
import { BillingAccessService } from './common/billing-access.service';
import { BillingCodeService } from './common/billing-code.service';
import { BillingDateService } from './common/billing-date.service';
import { BillingMoneyService } from './common/billing-money.service';
import { PayoutAccountCryptoService } from './common/payout-account-crypto.service';
import { CommissionEngineService } from './commissions/commission-engine.service';
import { CommissionsController } from './commissions/commissions.controller';
import { CommissionsService } from './commissions/commissions.service';
import { InvoicesController } from './invoices/invoices.controller';
import { InvoicesService } from './invoices/invoices.service';
import { PaymentsController } from './payments/payments.controller';
import { PaymentsService } from './payments/payments.service';
import { ServicePlansController } from './service-plans/service-plans.controller';
import { ServicePlansService } from './service-plans/service-plans.service';
import { PayoutAccountsService } from './settlements/payout-accounts.service';
import { SettlementsController } from './settlements/settlements.controller';
import { SettlementsService } from './settlements/settlements.service';
import { SubscriptionsController } from './subscriptions/subscriptions.controller';
import { SubscriptionsService } from './subscriptions/subscriptions.service';

@Module({
  imports: [ConfigModule, AccessControlModule, AuditModule],
  controllers: [
    ServicePlansController,
    SubscriptionsController,
    InvoicesController,
    PaymentsController,
    CommissionsController,
    SettlementsController,
  ],
  providers: [
    BillingAccessService,
    BillingCodeService,
    BillingDateService,
    BillingMoneyService,
    PayoutAccountCryptoService,
    CommissionEngineService,
    ServicePlansService,
    InvoicesService,
    SubscriptionsService,
    PaymentsService,
    CommissionsService,
    PayoutAccountsService,
    SettlementsService,
  ],
  exports: [
    BillingAccessService,
    BillingCodeService,
    BillingDateService,
    BillingMoneyService,
    CommissionEngineService,
    InvoicesService,
    PaymentsService,
  ],
})
export class BillingApiModule {}
