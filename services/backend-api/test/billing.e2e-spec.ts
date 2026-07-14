import type { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import type { TestingModule } from '@nestjs/testing';
import { randomInt, randomUUID } from 'node:crypto';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { configureApplication } from '../src/bootstrap/app.setup';
import { PrismaService } from '../src/database/prisma.service';
import { PasswordService } from '../src/identity/common/password.service';

describe('Billing, commission, and settlement lifecycle (e2e)', () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let accessToken: string;
  let platformUserId: string;
  let platformMembershipId: string;
  let platformRoleAssignmentId: string;
  let dealerId: string;
  let customerId: string;
  let vehicleId: string;
  let planId: string;
  let subscriptionId: string;
  let invoiceId: string;
  let paymentId: string;
  let commissionRuleId: string;
  let commissionEntryId: string;
  let payoutAccountId: string;
  let settlementId: string;

  const numericSuffix = randomInt(10_000_000, 100_000_000).toString();
  const codeSuffix = randomUUID().replace(/-/g, '').slice(0, 10).toUpperCase();
  const mobileNumber = `+88018${numericSuffix}`;
  const password = 'SolidTrackerTest123';

  beforeAll(async () => {
    const moduleFixture: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    app = moduleFixture.createNestApplication();
    configureApplication(app);
    await app.init();

    prisma = app.get(PrismaService);
    const passwordService = app.get(PasswordService);
    const passwordHash = await passwordService.hash(password);

    const platformOrganization = await prisma.organization.findUniqueOrThrow({
      where: {
        code: 'ORG-PLATFORM',
      },
    });

    const superAdminRole = await prisma.role.findUniqueOrThrow({
      where: {
        code: 'PLATFORM_SUPER_ADMIN',
      },
    });

    const user = await prisma.user.create({
      data: {
        userCode: `USR-BILL-${codeSuffix}`,
        fullName: 'Billing E2E Administrator',
        mobileNumber,
        normalizedMobileNumber: mobileNumber,
        passwordHash,
        passwordChangedAt: new Date(),
        status: 'ACTIVE',
        mobileVerifiedAt: new Date(),
      },
    });

    platformUserId = user.id;

    const membership = await prisma.organizationMembership.create({
      data: {
        organizationId: platformOrganization.id,
        userId: user.id,
        membershipType: 'EMPLOYEE',
        status: 'ACTIVE',
        isPrimary: true,
        joinedAt: new Date(),
      },
    });

    platformMembershipId = membership.id;

    const assignment = await prisma.roleAssignment.create({
      data: {
        userId: user.id,
        roleId: superAdminRole.id,
        organizationMembershipId: membership.id,
        scopeType: 'PLATFORM',
        scopeId: platformOrganization.id,
        status: 'ACTIVE',
        assignedByUserId: user.id,
      },
    });

    platformRoleAssignmentId = assignment.id;

    const loginResponse = await request(app.getHttpServer())
      .post('/api/v1/auth/login')
      .send({
        mobileNumber,
        password,
        platform: 'WEB',
        deviceName: 'Billing E2E',
        appVersion: 'test',
      })
      .expect(200);

    accessToken = loginResponse.body.accessToken as string;
  });

  afterAll(async () => {
    const now = new Date();

    if (prisma) {
      if (subscriptionId) {
        await prisma.subscription.update({
          where: {
            id: subscriptionId,
          },
          data: {
            status: 'CANCELLED',
            cancelledAt: now,
            cancellationReason: 'E2E cleanup',
            autoRenew: false,
            nextBillingAt: null,
          },
        });
      }

      if (payoutAccountId) {
        await prisma.dealerPayoutAccount.update({
          where: {
            id: payoutAccountId,
          },
          data: {
            status: 'ARCHIVED',
            isDefault: false,
            archivedAt: now,
          },
        });
      }

      if (commissionRuleId) {
        await prisma.commissionRule.update({
          where: {
            id: commissionRuleId,
          },
          data: {
            status: 'ARCHIVED',
            archivedAt: now,
          },
        });
      }

      if (planId) {
        await prisma.servicePlan.update({
          where: {
            id: planId,
          },
          data: {
            status: 'ARCHIVED',
            archivedAt: now,
          },
        });
      }

      if (vehicleId) {
        await prisma.vehicle.update({
          where: {
            id: vehicleId,
          },
          data: {
            status: 'ARCHIVED',
            archivedAt: now,
          },
        });
      }

      if (customerId) {
        await prisma.customer.update({
          where: {
            id: customerId,
          },
          data: {
            status: 'ARCHIVED',
            archivedAt: now,
          },
        });
      }

      if (dealerId) {
        await prisma.organization.update({
          where: {
            id: dealerId,
          },
          data: {
            status: 'ARCHIVED',
            archivedAt: now,
          },
        });
      }

      if (platformUserId) {
        await prisma.userSession.deleteMany({
          where: {
            userId: platformUserId,
          },
        });

        await prisma.roleAssignment.deleteMany({
          where: {
            id: platformRoleAssignmentId,
          },
        });

        await prisma.organizationMembership.deleteMany({
          where: {
            id: platformMembershipId,
          },
        });

        await prisma.user.update({
          where: {
            id: platformUserId,
          },
          data: {
            status: 'ARCHIVED',
            passwordHash: null,
            archivedAt: now,
          },
        });
      }
    }

    if (app) {
      await app.close();
    }
  });

  it('runs subscription, invoice, payment, commission, and settlement accounting', async () => {
    const dealerResponse = await request(app.getHttpServer())
      .post('/api/v1/dealers')
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        name: `Billing E2E Dealer ${codeSuffix}`,
        contactMobile: `017${numericSuffix}`,
      })
      .expect(201);

    dealerId = dealerResponse.body.id as string;

    const customerResponse = await request(app.getHttpServer())
      .post('/api/v1/customers/individual')
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        managingDealerId: dealerId,
        fullName: `Billing E2E Customer ${codeSuffix}`,
        primaryMobile: `016${numericSuffix}`,
      })
      .expect(201);

    customerId = customerResponse.body.id as string;

    const vehicleResponse = await request(app.getHttpServer())
      .post('/api/v1/vehicles')
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        customerId,
        vehicleType: 'CAR',
        registrationNumber: `BILL-E2E-${codeSuffix}`,
        manufacturer: 'Solid Tracker Test',
        modelName: 'Billing Car',
        manufacturingYear: 2026,
      })
      .expect(201);

    vehicleId = vehicleResponse.body.id as string;

    const effectiveFrom = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();

    const planResponse = await request(app.getHttpServer())
      .post('/api/v1/service-plans')
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        planFamilyCode: `MONTHLY_${codeSuffix}`,
        name: `Monthly Tracking ${codeSuffix}`,
        billingIntervalUnit: 'MONTH',
        billingIntervalCount: 1,
        basePrice: '500.00',
        currency: 'BDT',
        taxBehavior: 'NONE',
        trialDays: 0,
        effectiveFrom,
        features: {
          liveTracking: true,
          historyDays: 90,
        },
      })
      .expect(201);

    planId = planResponse.body.id as string;

    await request(app.getHttpServer())
      .post(`/api/v1/service-plans/${planId}/activate`)
      .set('Authorization', `Bearer ${accessToken}`)
      .send({})
      .expect(201);

    const subscriptionResponse = await request(app.getHttpServer())
      .post('/api/v1/subscriptions')
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        customerId,
        vehicleId,
        servicePlanId: planId,
        autoRenew: true,
      })
      .expect(201);

    subscriptionId = subscriptionResponse.body.id as string;

    await request(app.getHttpServer())
      .post(`/api/v1/subscriptions/${subscriptionId}/activate`)
      .set('Authorization', `Bearer ${accessToken}`)
      .send({})
      .expect(201);

    const invoiceResponse = await request(app.getHttpServer())
      .post(`/api/v1/subscriptions/${subscriptionId}/generate-invoice`)
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        dueInDays: 7,
      })
      .expect(201);

    invoiceId = invoiceResponse.body.id as string;
    expect(Number(invoiceResponse.body.totalAmount)).toBe(500);

    await request(app.getHttpServer())
      .post(`/api/v1/invoices/${invoiceId}/issue`)
      .set('Authorization', `Bearer ${accessToken}`)
      .send({})
      .expect(201);

    const ruleResponse = await request(app.getHttpServer())
      .post('/api/v1/commission-rules')
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        dealerOrganizationId: dealerId,
        servicePlanId: planId,
        transactionType: 'INITIAL_SUBSCRIPTION',
        calculationType: 'PERCENTAGE',
        percentageRate: '10.0000',
        priority: 10,
        effectiveFrom,
      })
      .expect(201);

    commissionRuleId = ruleResponse.body.id as string;

    await request(app.getHttpServer())
      .patch(`/api/v1/commission-rules/${commissionRuleId}`)
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        status: 'ACTIVE',
      })
      .expect(200);

    const paymentResponse = await request(app.getHttpServer())
      .post('/api/v1/payments')
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        customerId,
        amount: '500.00',
        currency: 'BDT',
        paymentMethod: 'CASH',
        paymentGateway: 'MANUAL',
        gatewayReference: `CASH-${codeSuffix}`,
      })
      .expect(201);

    paymentId = paymentResponse.body.id as string;

    const confirmedPaymentResponse = await request(app.getHttpServer())
      .post(`/api/v1/payments/${paymentId}/confirm`)
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        gatewayTransactionId: `TXN-${codeSuffix}`,
        allocations: [
          {
            invoiceId,
            amount: '500.00',
          },
        ],
      })
      .expect(201);

    expect(confirmedPaymentResponse.body.status).toBe('SUCCEEDED');
    expect(confirmedPaymentResponse.body.allocations).toHaveLength(1);
    expect(confirmedPaymentResponse.body.commissionEntries).toHaveLength(1);

    const commissionResponse = await request(app.getHttpServer())
      .get(`/api/v1/commissions?dealerOrganizationId=${dealerId}`)
      .set('Authorization', `Bearer ${accessToken}`)
      .expect(200);

    expect(commissionResponse.body.items).toHaveLength(1);
    commissionEntryId = commissionResponse.body.items[0].id as string;
    expect(Number(commissionResponse.body.items[0].commissionAmount)).toBe(50);

    const payoutResponse = await request(app.getHttpServer())
      .post('/api/v1/dealer-payout-accounts')
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        dealerOrganizationId: dealerId,
        accountType: 'MOBILE_FINANCIAL_SERVICE',
        provider: 'BKASH',
        accountHolderName: `Dealer ${codeSuffix}`,
        accountReference: `019${numericSuffix}`,
        isDefault: true,
      })
      .expect(201);

    payoutAccountId = payoutResponse.body.id as string;
    expect(payoutResponse.body.encryptedAccountReference).toBeUndefined();

    await request(app.getHttpServer())
      .post(`/api/v1/dealer-payout-accounts/${payoutAccountId}/verify`)
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        verificationStatus: 'VERIFIED',
      })
      .expect(201);

    const settlementResponse = await request(app.getHttpServer())
      .post('/api/v1/settlements')
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        dealerOrganizationId: dealerId,
        payoutAccountId,
        commissionEntryIds: [commissionEntryId],
        adjustmentAmount: '0.00',
        feeAmount: '0.00',
      })
      .expect(201);

    settlementId = settlementResponse.body.id as string;
    expect(Number(settlementResponse.body.netSettlementAmount)).toBe(50);

    await request(app.getHttpServer())
      .post(`/api/v1/settlements/${settlementId}/submit`)
      .set('Authorization', `Bearer ${accessToken}`)
      .send({})
      .expect(201);

    const completedSettlementResponse = await request(app.getHttpServer())
      .post(`/api/v1/settlements/${settlementId}/complete`)
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        providerReference: `PAYOUT-${codeSuffix}`,
      })
      .expect(201);

    expect(completedSettlementResponse.body.status).toBe('COMPLETED');

    const ledgerResponse = await request(app.getHttpServer())
      .get(`/api/v1/dealers/${dealerId}/ledger`)
      .set('Authorization', `Bearer ${accessToken}`)
      .expect(200);

    expect(ledgerResponse.body.items).toHaveLength(2);
    expect(Number(ledgerResponse.body.balance)).toBe(0);
  });
});
