import type { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import type { TestingModule } from '@nestjs/testing';
import { createServer, type Server } from 'node:http';
import type { AddressInfo } from 'node:net';
import { randomInt, randomUUID } from 'node:crypto';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { configureApplication } from '../src/bootstrap/app.setup';
import { PrismaService } from '../src/database/prisma.service';
import { PasswordService } from '../src/identity/common/password.service';
import { TokenService } from '../src/identity/common/token.service';
import { TrackingCredentialCryptoService } from '../src/tracking/common/tracking-credential-crypto.service';

describe('Customer mobile API (e2e)', () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let fakeTraccar: Server;
  let fakeTraccarBaseUrl: string;
  let accessToken: string;
  let userId: string;
  let customerId: string;
  let customerMembershipId: string;
  let roleAssignmentId: string;
  let vehicleId: string;
  let deviceId: string;
  let deviceModelId: string;
  let assignmentId: string;
  let traccarServerId: string;
  let mappingId: string;
  let servicePlanId: string;
  let subscriptionId: string;
  let eventId: string;

  const numericSuffix = randomInt(10_000_000, 100_000_000).toString();
  const codeSuffix = randomUUID().replace(/-/g, '').slice(0, 10).toUpperCase();
  const mobileNumber = `+88016${numericSuffix}`;
  const password = 'SolidTrackerMobile123';

  beforeAll(async () => {
    fakeTraccar = createServer((incoming, outgoing) => {
      const url = new URL(incoming.url ?? '/', 'http://localhost');

      if (incoming.method === 'GET' && url.pathname === '/api/positions') {
        outgoing.setHeader('Content-Type', 'application/json');
        outgoing.end(
          JSON.stringify([
            {
              id: 7001,
              deviceId: 101,
              protocol: 'osmand',
              serverTime: '2026-07-14T10:00:00.000Z',
              deviceTime: '2026-07-14T10:00:00.000Z',
              fixTime: '2026-07-14T10:00:00.000Z',
              valid: true,
              latitude: 23.8103,
              longitude: 90.4125,
              altitude: 8,
              speed: 12,
              course: 180,
              accuracy: 5,
              attributes: {
                ignition: true,
              },
            },
            {
              id: 7002,
              deviceId: 101,
              protocol: 'osmand',
              serverTime: '2026-07-14T10:05:00.000Z',
              deviceTime: '2026-07-14T10:05:00.000Z',
              fixTime: '2026-07-14T10:05:00.000Z',
              valid: true,
              latitude: 23.8203,
              longitude: 90.4225,
              altitude: 8,
              speed: 14,
              course: 180,
              accuracy: 5,
              attributes: {
                ignition: true,
              },
            },
            {
              id: 7003,
              deviceId: 101,
              protocol: 'osmand',
              serverTime: '2026-07-14T10:06:00.000Z',
              deviceTime: '2026-07-14T10:06:00.000Z',
              fixTime: '2026-07-14T10:06:00.000Z',
              valid: true,
              latitude: 23.8203,
              longitude: 90.4225,
              altitude: 8,
              speed: 0,
              course: 180,
              accuracy: 5,
              attributes: {
                ignition: false,
              },
            },
          ]),
        );
        return;
      }

      outgoing.statusCode = 404;
      outgoing.end();
    });

    await new Promise<void>((resolve) => {
      fakeTraccar.listen(0, '127.0.0.1', resolve);
    });

    const address = fakeTraccar.address() as AddressInfo;
    fakeTraccarBaseUrl = `http://127.0.0.1:${address.port}`;

    const moduleFixture: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    app = moduleFixture.createNestApplication();
    configureApplication(app);
    await app.init();

    prisma = app.get(PrismaService);
    const passwordService = app.get(PasswordService);
    const tokenService = app.get(TokenService);
    const credentialCrypto = app.get(TrackingCredentialCryptoService);
    const passwordHash = await passwordService.hash(password);

    const customer = await prisma.customer.create({
      data: {
        customerCode: `CUS-MOB-${codeSuffix}`,
        customerType: 'INDIVIDUAL',
        status: 'ACTIVE',
        acquisitionSource: 'DIRECT',
        primaryMobile: mobileNumber,
        individualProfile: {
          create: {
            fullName: 'Mobile API E2E Customer',
          },
        },
      },
    });

    customerId = customer.id;

    const user = await prisma.user.create({
      data: {
        userCode: `USR-MOB-${codeSuffix}`,
        fullName: 'Mobile API E2E User',
        mobileNumber,
        normalizedMobileNumber: mobileNumber,
        passwordHash,
        passwordChangedAt: new Date(),
        status: 'ACTIVE',
        mobileVerifiedAt: new Date(),
      },
    });

    userId = user.id;

    const membership = await prisma.customerMembership.create({
      data: {
        customerId,
        userId,
        status: 'ACTIVE',
        isPrimary: true,
        joinedAt: new Date(),
      },
    });

    customerMembershipId = membership.id;

    const customerOwnerRole = await prisma.role.findUniqueOrThrow({
      where: {
        code: 'CUSTOMER_OWNER',
      },
    });
    const roleAssignment = await prisma.roleAssignment.create({
      data: {
        userId,
        roleId: customerOwnerRole.id,
        scopeType: 'CUSTOMER',
        scopeId: customerId,
        status: 'ACTIVE',
        assignedByUserId: userId,
      },
    });

    roleAssignmentId = roleAssignment.id;

    const deviceModel = await prisma.deviceModel.create({
      data: {
        modelCode: `DM-MOB-${codeSuffix}`,
        manufacturer: 'Solid Tracker',
        modelName: 'Mobile E2E Tracker',
        protocol: 'osmand',
        networkType: 'LTE_4G',
        status: 'ACTIVE',
      },
    });

    deviceModelId = deviceModel.id;

    const device = await prisma.device.create({
      data: {
        deviceCode: `DEV-MOB-${codeSuffix}`,
        deviceModelId,
        imei: `86${numericSuffix}12345`,
        lifecycleStatus: 'INSTALLED',
        receivedAt: new Date(),
      },
    });

    deviceId = device.id;

    const vehicle = await prisma.vehicle.create({
      data: {
        vehicleCode: `VEH-MOB-${codeSuffix}`,
        customerId,
        registrationNumber: `DHAKA-METRO-${codeSuffix}`,
        normalizedRegistrationNumber: `DHAKA-METRO-${codeSuffix}`,
        vehicleType: 'CAR',
        manufacturer: 'Toyota',
        modelName: 'Corolla',
        manufacturingYear: 2022,
        color: 'White',
        status: 'ACTIVE',
        createdByUserId: userId,
      },
    });

    vehicleId = vehicle.id;

    const assignment = await prisma.vehicleDeviceAssignment.create({
      data: {
        vehicleId,
        deviceId,
        assignmentType: 'PRIMARY',
        status: 'ACTIVE',
        assignedByUserId: userId,
      },
    });

    assignmentId = assignment.id;

    const traccarServer = await prisma.traccarServer.create({
      data: {
        serverCode: `TRC-MOB-${codeSuffix}`,
        name: 'Mobile E2E Traccar',
        baseUrl: fakeTraccarBaseUrl,
        encryptedCredentialReference: credentialCrypto.encrypt({
          token: 'mobile-e2e-token',
        }),
        status: 'ACTIVE',
        isDefault: false,
        lastHealthStatus: 'UP',
      },
    });

    traccarServerId = traccarServer.id;

    const mapping = await prisma.traccarDeviceMapping.create({
      data: {
        deviceId,
        traccarServerId,
        traccarDeviceId: 101n,
        traccarUniqueId: `MOBILE-${codeSuffix}`,
        syncStatus: 'SYNCED',
        isPrimary: true,
        isActive: true,
        lastSyncedAt: new Date(),
      },
    });

    mappingId = mapping.id;

    const servicePlan = await prisma.servicePlan.create({
      data: {
        planCode: `PLAN-MOB-${codeSuffix}`,
        planFamilyCode: `MOBILE-${codeSuffix}`,
        version: 1,
        name: 'Mobile E2E Plan',
        billingIntervalUnit: 'MONTH',
        billingIntervalCount: 1,
        basePrice: '500.00',
        currency: 'BDT',
        status: 'ACTIVE',
        effectiveFrom: new Date(),
      },
    });

    servicePlanId = servicePlan.id;

    const subscription = await prisma.subscription.create({
      data: {
        subscriptionCode: `SUB-MOB-${codeSuffix}`,
        customerId,
        vehicleId,
        servicePlanId,
        status: 'ACTIVE',
        startedAt: new Date(),
        currentPeriodStart: new Date(),
        currentPeriodEnd: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000),
        nextBillingAt: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000),
        autoRenew: true,
      },
    });

    subscriptionId = subscription.id;

    const event = await prisma.trackingEvent.create({
      data: {
        eventCode: `EVT-MOB-${codeSuffix}`,
        customerId,
        vehicleId,
        deviceId,
        traccarServerId,
        deduplicationKey: `mobile-e2e-${codeSuffix}`,
        eventType: 'deviceOnline',
        severity: 'INFO',
        latitude: '23.8103000',
        longitude: '90.4125000',
        occurredAt: new Date(),
        processingStatus: 'PROCESSED',
      },
    });

    eventId = event.id;

    const refreshToken = tokenService.createRefreshToken();
    const session = await prisma.userSession.create({
      data: {
        userId,
        tokenFamilyId: randomUUID(),
        refreshTokenHash: tokenService.hashRefreshToken(refreshToken),
        platform: 'ANDROID',
        deviceName: 'Mobile API E2E',
        appVersion: 'test',
        expiresAt: tokenService.getRefreshExpiry(),
      },
    });

    accessToken = await tokenService.signAccessToken(userId, session.id);
  });

  afterAll(async () => {
    if (prisma) {
      await prisma.userSession.deleteMany({
        where: {
          userId,
        },
      });
      await prisma.integrationJob.deleteMany({
        where: {
          entityId: vehicleId,
        },
      });
      await prisma.trackingEvent.deleteMany({
        where: {
          id: eventId,
        },
      });
      await prisma.subscription.deleteMany({
        where: {
          id: subscriptionId,
        },
      });
      await prisma.servicePlan.deleteMany({
        where: {
          id: servicePlanId,
        },
      });
      await prisma.traccarDeviceMapping.deleteMany({
        where: {
          id: mappingId,
        },
      });
      await prisma.traccarServer.deleteMany({
        where: {
          id: traccarServerId,
        },
      });
      await prisma.vehicleDeviceAssignment.deleteMany({
        where: {
          id: assignmentId,
        },
      });
      await prisma.device.deleteMany({
        where: {
          id: deviceId,
        },
      });
      await prisma.deviceModel.deleteMany({
        where: {
          id: deviceModelId,
        },
      });
      await prisma.vehicle.deleteMany({
        where: {
          id: vehicleId,
        },
      });
      await prisma.roleAssignment.deleteMany({
        where: {
          id: roleAssignmentId,
        },
      });
      await prisma.customerMembership.deleteMany({
        where: {
          id: customerMembershipId,
        },
      });
      await prisma.customer.deleteMany({
        where: {
          id: customerId,
        },
      });
      await prisma.user.deleteMany({
        where: {
          id: userId,
        },
      });
    }

    if (app) {
      await app.close();
    }

    if (fakeTraccar) {
      await new Promise<void>((resolve, reject) => {
        fakeTraccar.close((error) => {
          if (error) {
            reject(error);
            return;
          }

          resolve();
        });
      });
    }
  });

  it('serves dashboard, vehicle, trip, event, billing, and live-session contracts', async () => {
    const authorization = `Bearer ${accessToken}`;

    const profile = await request(app.getHttpServer())
      .get('/api/v1/mobile/profile')
      .set('Authorization', authorization)
      .expect(200);

    expect(profile.body.data.id).toBe(userId);
    expect(profile.body.data.customerMemberships).toHaveLength(1);

    const dashboard = await request(app.getHttpServer())
      .get('/api/v1/mobile/dashboard')
      .set('Authorization', authorization)
      .expect(200);

    expect(dashboard.body.data.summary.vehicleCount).toBe(1);

    const vehicles = await request(app.getHttpServer())
      .get('/api/v1/mobile/vehicles')
      .set('Authorization', authorization)
      .expect(200);

    expect(vehicles.body.data).toHaveLength(1);
    expect(vehicles.body.data[0].id).toBe(vehicleId);

    const session = await request(app.getHttpServer())
      .post('/api/v1/mobile/live-sessions')
      .set('Authorization', authorization)
      .send({
        vehicleId,
        ttlSeconds: 120,
      })
      .expect(201);
    const sessionToken = session.body.data.token as string;

    const position = await request(app.getHttpServer())
      .get(`/api/v1/mobile/live-sessions/${sessionToken}/position`)
      .set('Authorization', authorization)
      .expect(200);

    expect(position.body.data.position.latitude).toBe(23.8203);

    const trips = await request(app.getHttpServer())
      .get(`/api/v1/mobile/vehicles/${vehicleId}/trips`)
      .query({
        from: '2026-07-14T09:00:00.000Z',
        to: '2026-07-14T11:00:00.000Z',
      })
      .set('Authorization', authorization)
      .expect(200);

    expect(trips.body.data).toHaveLength(1);

    const events = await request(app.getHttpServer())
      .get(`/api/v1/mobile/vehicles/${vehicleId}/events`)
      .set('Authorization', authorization)
      .expect(200);

    expect(events.body.data).toHaveLength(1);

    const subscriptions = await request(app.getHttpServer())
      .get('/api/v1/mobile/billing/subscriptions')
      .set('Authorization', authorization)
      .expect(200);

    expect(subscriptions.body.data).toHaveLength(1);

    await request(app.getHttpServer())
      .delete(`/api/v1/mobile/live-sessions/${sessionToken}`)
      .set('Authorization', authorization)
      .expect(200);
  });
});
