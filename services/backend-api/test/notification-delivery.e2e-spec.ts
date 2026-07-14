import type { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import type { TestingModule } from '@nestjs/testing';
import { randomInt, randomUUID } from 'node:crypto';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { configureApplication } from '../src/bootstrap/app.setup';
import { PrismaService } from '../src/database/prisma.service';
import { PasswordService } from '../src/identity/common/password.service';
import { NotificationSignatureService } from '../src/notification-delivery/common/notification-signature.service';

describe('Notification delivery (e2e)', () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let signatures: NotificationSignatureService;
  let accessToken: string;
  let platformUserId: string;
  let platformMembershipId: string;
  let platformRoleAssignmentId: string;
  let customerId: string;
  let templateId: string;
  let notificationId: string;

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
    signatures = app.get(NotificationSignatureService);
    const passwordService = app.get(PasswordService);
    const passwordHash = await passwordService.hash(password);
    const platformOrganization = await prisma.organization.findUniqueOrThrow({
      where: { code: 'ORG-PLATFORM' },
    });
    const superAdminRole = await prisma.role.findUniqueOrThrow({
      where: { code: 'PLATFORM_SUPER_ADMIN' },
    });
    const user = await prisma.user.create({
      data: {
        userCode: `USR-NTF-${codeSuffix}`,
        fullName: 'Notification Delivery E2E Administrator',
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
        deviceName: 'Notification Delivery E2E',
        appVersion: 'test',
      })
      .expect(200);

    accessToken = loginResponse.body.accessToken as string;
  });

  afterAll(async () => {
    const now = new Date();

    if (prisma) {
      if (templateId) {
        await prisma.notificationTemplate.update({
          where: { id: templateId },
          data: {
            status: 'ARCHIVED',
            archivedAt: now,
          },
        });
      }

      if (customerId) {
        await prisma.customer.update({
          where: { id: customerId },
          data: {
            status: 'ARCHIVED',
            archivedAt: now,
          },
        });
      }

      if (platformUserId) {
        await prisma.userSession.deleteMany({
          where: { userId: platformUserId },
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
          where: { id: platformUserId },
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

  it('renders, dispatches, and idempotently confirms a notification', async () => {
    const customerResponse = await request(app.getHttpServer())
      .post('/api/v1/customers/individual')
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        fullName: `Notification Customer ${codeSuffix}`,
        primaryMobile: `016${numericSuffix}`,
      })
      .expect(201);

    customerId = customerResponse.body.id as string;

    const templateResponse = await request(app.getHttpServer())
      .post('/api/v1/notification-templates')
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        templateKey: `e2e.notification.${codeSuffix.toLowerCase()}`,
        channel: 'EMAIL',
        locale: 'en',
        name: `E2E Email Template ${codeSuffix}`,
        subjectTemplate: 'Alert for {{customer.name}}',
        bodyTemplate: 'Vehicle {{vehicle}} generated {{event}}.',
        variableSchema: {
          required: ['customer.name', 'vehicle', 'event'],
        },
        activate: true,
      })
      .expect(201);

    templateId = templateResponse.body.id as string;

    const previewResponse = await request(app.getHttpServer())
      .post(`/api/v1/notification-templates/${templateId}/preview`)
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        variables: {
          customer: { name: 'Test Customer' },
          vehicle: 'DHAKA-01',
          event: 'overspeed',
        },
      })
      .expect(201);

    expect(previewResponse.body.subject).toBe('Alert for Test Customer');

    const enqueueResponse = await request(app.getHttpServer())
      .post('/api/v1/notification-delivery/enqueue')
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        customerId,
        channel: 'EMAIL',
        recipient: `notify-${codeSuffix}@example.com`,
        templateKey: `e2e.notification.${codeSuffix.toLowerCase()}`,
        locale: 'en',
        variables: {
          customer: { name: 'Test Customer' },
          vehicle: 'DHAKA-01',
          event: 'overspeed',
        },
      })
      .expect(201);

    notificationId = enqueueResponse.body.id as string;

    const runResponse = await request(app.getHttpServer())
      .post('/api/v1/notification-delivery/run')
      .set('Authorization', `Bearer ${accessToken}`)
      .send({ batchSize: 200 })
      .expect(201);

    expect(runResponse.body.succeeded).toBeGreaterThanOrEqual(1);

    const notification = await prisma.notification.findUniqueOrThrow({
      where: { id: notificationId },
    });

    expect(notification.status).toBe('SENT');
    expect(notification.provider).toBe('SANDBOX');
    expect(notification.providerMessageId).toBeTruthy();

    const attemptsResponse = await request(app.getHttpServer())
      .get(`/api/v1/notification-delivery/${notificationId}/attempts`)
      .set('Authorization', `Bearer ${accessToken}`)
      .expect(200);

    expect(attemptsResponse.body).toHaveLength(1);
    expect(attemptsResponse.body[0].status).toBe('SENT');

    const callbackBody = {
      externalEventId: `NTF-E2E-${codeSuffix}-${randomUUID()}`,
      providerMessageId: notification.providerMessageId as string,
      status: 'DELIVERED',
      occurredAt: new Date().toISOString(),
      metadata: {
        source: 'e2e',
      },
    };
    const timestamp = Date.now().toString();
    const secret = process.env.NOTIFICATION_SANDBOX_WEBHOOK_SECRET;

    expect(secret).toBeDefined();

    const signature = signatures.sign(
      secret as string,
      timestamp,
      callbackBody.externalEventId,
      callbackBody,
    );

    const firstCallback = await request(app.getHttpServer())
      .post('/api/v1/notification-delivery/callbacks/SANDBOX')
      .set('x-solid-timestamp', timestamp)
      .set('x-solid-event-id', callbackBody.externalEventId)
      .set('x-solid-signature', signature)
      .send(callbackBody)
      .expect(201);

    expect(firstCallback.body.idempotent).toBe(false);

    const duplicateCallback = await request(app.getHttpServer())
      .post('/api/v1/notification-delivery/callbacks/SANDBOX')
      .set('x-solid-timestamp', timestamp)
      .set('x-solid-event-id', callbackBody.externalEventId)
      .set('x-solid-signature', signature)
      .send(callbackBody)
      .expect(201);

    expect(duplicateCallback.body.idempotent).toBe(true);

    const delivered = await prisma.notification.findUniqueOrThrow({
      where: { id: notificationId },
    });

    expect(delivered.status).toBe('DELIVERED');
    expect(delivered.deliveredAt).not.toBeNull();

    const metricsResponse = await request(app.getHttpServer())
      .get('/api/v1/notification-delivery/metrics')
      .set('Authorization', `Bearer ${accessToken}`)
      .expect(200);

    expect(metricsResponse.body.notifications.DELIVERED).toBeGreaterThanOrEqual(1);
  });
});
