import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { BillingApiModule } from '../billing/billing-api.module';
import { AccessControlModule } from '../identity/access-control/access-control.module';
import { AuditModule } from '../identity/audit/audit.module';
import { BkashGatewayAdapter } from './adapters/bkash-gateway.adapter';
import { GatewayRegistryService } from './adapters/gateway-registry.service';
import { NagadGatewayAdapter } from './adapters/nagad-gateway.adapter';
import { SandboxGatewayAdapter } from './adapters/sandbox-gateway.adapter';
import { SignedProxyClientService } from './adapters/signed-proxy-client.service';
import { SslCommerzGatewayAdapter } from './adapters/sslcommerz-gateway.adapter';
import { AutomationIdentityService } from './common/automation-identity.service';
import { AutomationRunKeyService } from './common/automation-run-key.service';
import { GatewayHttpService } from './common/gateway-http.service';
import { GatewaySignatureService } from './common/gateway-signature.service';
import { BillingAutomationController } from './controllers/billing-automation.controller';
import { PaymentGatewayWebhookController } from './controllers/payment-gateway-webhook.controller';
import { PaymentGatewayController } from './controllers/payment-gateway.controller';
import { GatewayPaymentService } from './services/gateway-payment.service';
import { PaymentReconciliationService } from './services/payment-reconciliation.service';
import { RecurringBillingService } from './services/recurring-billing.service';

@Module({
  imports: [ConfigModule, BillingApiModule, AccessControlModule, AuditModule],
  controllers: [
    PaymentGatewayController,
    PaymentGatewayWebhookController,
    BillingAutomationController,
  ],
  providers: [
    GatewaySignatureService,
    GatewayHttpService,
    AutomationRunKeyService,
    AutomationIdentityService,
    SignedProxyClientService,
    SandboxGatewayAdapter,
    BkashGatewayAdapter,
    NagadGatewayAdapter,
    SslCommerzGatewayAdapter,
    GatewayRegistryService,
    GatewayPaymentService,
    PaymentReconciliationService,
    RecurringBillingService,
  ],
})
export class PaymentGatewayAutomationModule {}
