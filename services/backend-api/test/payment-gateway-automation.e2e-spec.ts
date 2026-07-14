import type { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import type { TestingModule } from '@nestjs/testing';
import { randomInt, randomUUID } from 'node:crypto';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { configureApplication } from '../src/bootstrap/app.setup';
import { PrismaService } from '../src/database/prisma.service';
import { PasswordService } from '../src/identity/common/password.service';
import { GatewaySignatureService } from '../src/payment-automation/common/gateway-signature.service';

describe('Payment gateway and recurring billing automation (e2e)', () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let signatures: GatewaySignatureService;
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

  const numericSuffix = randomInt(10_000_000, 100_000_000).toString();
  const codeSuffix = randomUUID().replace(/-/g, '').slice(0, 10).toUpperCase();
  const mobileNumber = `+88015${numericSuffix}`;
  const password = 'SolidTrackerTest123';

  beforeAll(async () => {
    const moduleFixture: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    app = moduleFixture.createNestApplication();
    configureApplication(app);
    await app.init();

    prisma = app.get(PrismaService);
    signatures = app.get(GatewaySignatureService);
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
        userCode: `USR-PAY-${codeSuffix}`,
        fullName: 'Payment Automation E2E Administrator',
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
        deviceName: 'Payment Automation E2E',
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

  it('generates a recurring invoice and confirms it through an idempotent signed callback', async () => {
    const dealerResponse = await request(app.getHttpServer())
      .post('/api/v1/dealers')
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        name: `Gateway E2E Dealer ${codeSuffix}`,
        contactMobile: `017${numericSuffix}`,
      })
      .expect(201);

    dealerId = dealerResponse.body.id as string;

    const customerResponse = await request(app.getHttpServer())
      .post('/api/v1/customers/individual')
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        managingDealerId: dealerId,
        fullName: `Gateway E2E Customer ${codeSuffix}`,
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
        registrationNumber: `PAY-E2E-${codeSuffix}`,
        manufacturer: 'Solid Tracker Test',
        modelName: 'Automation Car',
        manufacturingYear: 2026,
      })
      .expect(201);

    vehicleId = vehicleResponse.body.id as string;

    const effectiveFrom = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();

    const planResponse = await request(app.getHttpServer())
      .post('/api/v1/service-plans')
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        planFamilyCode: `AUTO_${codeSuffix}`,
        name: `Automated Monthly ${codeSuffix}`,
        billingIntervalUnit: 'MONTH',
        billingIntervalCount: 1,
        basePrice: '500.00',
        currency: 'BDT',
        taxBehavior: 'NONE',
        trialDays: 0,
        effectiveFrom,
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

    const periodStart = new Date(Date.now() - 40 * 24 * 60 * 60 * 1000);
    const periodEnd = new Date(Date.now() - 10 * 24 * 60 * 60 * 1000);

    await prisma.subscription.update({
      where: {
        id: subscriptionId,
      },
      data: {
        status: 'ACTIVE',
        currentPeriodStart: periodStart,
        currentPeriodEnd: periodEnd,
        nextBillingAt: periodEnd,
      },
    });

    const asOf = new Date(Date.now() + randomInt(2, 120) * 60 * 1000);

    const automationResponse = await request(app.getHttpServer())
      .post('/api/v1/billing-automation/run')
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        asOf: asOf.toISOString(),
        dueInDays: 7,
        batchSize: 10,
        dryRun: false,
      })
      .expect(201);

    expect(automationResponse.body.succeeded).toBe(1);

    const invoice = await prisma.invoice.findFirstOrThrow({
      where: {
        subscriptionId,
        status: 'ISSUED',
      },
      orderBy: {
        createdAt: 'desc',
      },
    });

    invoiceId = invoice.id;

    const paymentResponse = await request(app.getHttpServer())
      .post('/api/v1/payments')
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        customerId,
        amount: invoice.totalAmount.toString(),
        currency: invoice.currency,
        paymentMethod: 'CARD',
        paymentGateway: 'OTHER',
      })
      .expect(201);

    paymentId = paymentResponse.body.id as string;

    const initializationResponse = await request(app.getHttpServer())
      .post(`/api/v1/payments/${paymentId}/gateway/initialize`)
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        invoiceId,
        successUrl: 'http://localhost/payment/success',
        cancelUrl: 'http://localhost/payment/cancel',
        failureUrl: 'http://localhost/payment/failure',
      })
      .expect(201);

    const gatewayReference = initializationResponse.body.gatewayReference as string;
    const eventId = `E2E-${codeSuffix}-${randomUUID()}`;
    const payload = {
      eventId,
      paymentReference: gatewayReference,
      transactionId: `SANDBOX-TXN-${codeSuffix}`,
      status: 'SUCCEEDED',
      amount: invoice.totalAmount.toString(),
      currency: invoice.currency,
    };
    const secret = process.env.PAYMENT_SANDBOX_WEBHOOK_SECRET;

    expect(secret).toBeDefined();

    const signature = signatures.sign(secret as string, payload);

    const callbackResponse = await request(app.getHttpServer())
      .post('/api/v1/payment-gateways/webhooks/OTHER')
      .set('x-solid-signature', signature)
      .set('x-solid-event-id', eventId)
      .send(payload)
      .expect(201);

    expect(callbackResponse.body.payment.status).toBe('SUCCEEDED');

    const repeatedCallback = await request(app.getHttpServer())
      .post('/api/v1/payment-gateways/webhooks/OTHER')
      .set('x-solid-signature', signature)
      .set('x-solid-event-id', eventId)
      .send(payload)
      .expect(201);

    expect(repeatedCallback.body.idempotent).toBe(true);

    const storedPayment = await prisma.payment.findUniqueOrThrow({
      where: {
        id: paymentId,
      },
      include: {
        allocations: true,
      },
    });
    const storedInvoice = await prisma.invoice.findUniqueOrThrow({
      where: {
        id: invoiceId,
      },
    });
    const storedEvent = await prisma.paymentGatewayEvent.findUniqueOrThrow({
      where: {
        gateway_externalEventId: {
          gateway: 'OTHER',
          externalEventId: eventId,
        },
      },
    });

    expect(storedPayment.status).toBe('SUCCEEDED');
    expect(storedPayment.allocations).toHaveLength(1);
    expect(storedInvoice.status).toBe('PAID');
    expect(storedEvent.status).toBe('PROCESSED');
  });
});
