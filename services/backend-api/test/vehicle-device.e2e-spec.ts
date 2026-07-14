import type { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import type { TestingModule } from '@nestjs/testing';
import { randomInt, randomUUID } from 'node:crypto';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { configureApplication } from '../src/bootstrap/app.setup';
import { PrismaService } from '../src/database/prisma.service';
import { PasswordService } from '../src/identity/common/password.service';

describe('Vehicle and device lifecycle (e2e)', () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let accessToken: string;
  let platformUserId: string;
  let platformMembershipId: string;
  let platformRoleAssignmentId: string;
  let dealerId: string;
  let customerId: string;
  let vehicleId: string;
  let deviceModelId: string;
  let firstDeviceId: string;
  let replacementDeviceId: string;

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
        userCode: `USR-E2E-${codeSuffix}`,
        fullName: 'Vehicle Device E2E Administrator',
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
        deviceName: 'Vehicle Device E2E',
        appVersion: 'test',
      })
      .expect(200);

    accessToken = loginResponse.body.accessToken as string;
  });

  afterAll(async () => {
    const now = new Date();

    if (prisma) {
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

      for (const deviceId of [firstDeviceId, replacementDeviceId]) {
        if (deviceId) {
          await prisma.device.update({
            where: {
              id: deviceId,
            },
            data: {
              lifecycleStatus: 'RETIRED',
              retiredAt: now,
            },
          });
        }
      }

      if (deviceModelId) {
        await prisma.deviceModel.update({
          where: {
            id: deviceModelId,
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

  it('registers, allocates, installs, replaces, removes, and returns devices', async () => {
    const dealerResponse = await request(app.getHttpServer())
      .post('/api/v1/dealers')
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        name: `Asset E2E Dealer ${codeSuffix}`,
        contactMobile: `017${numericSuffix}`,
      })
      .expect(201);

    dealerId = dealerResponse.body.id as string;

    const customerResponse = await request(app.getHttpServer())
      .post('/api/v1/customers/individual')
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        managingDealerId: dealerId,
        fullName: `Asset E2E Customer ${codeSuffix}`,
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
        registrationNumber: `DHAKA-E2E-${codeSuffix}`,
        manufacturer: 'Solid Tracker Test',
        modelName: 'Lifecycle Car',
        manufacturingYear: 2026,
      })
      .expect(201);

    vehicleId = vehicleResponse.body.id as string;

    const modelResponse = await request(app.getHttpServer())
      .post('/api/v1/device-models')
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        manufacturer: `Solid Tracker E2E ${codeSuffix}`,
        modelName: 'ST-100',
        protocol: 'osmand',
        networkType: 'LTE_4G',
        capabilities: {
          ignition: true,
          relay: true,
          sos: true,
        },
      })
      .expect(201);

    deviceModelId = modelResponse.body.id as string;

    const imeiSuffix = `${Date.now()}`.slice(-13).padStart(13, '0');

    const firstDeviceResponse = await request(app.getHttpServer())
      .post('/api/v1/devices')
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        deviceModelId,
        imei: `86${imeiSuffix}`,
        serialNumber: `ST-E2E-A-${codeSuffix}`,
        hardwareVersion: '1.0',
        firmwareVersion: '1.0.0',
      })
      .expect(201);

    firstDeviceId = firstDeviceResponse.body.id as string;

    const replacementDeviceResponse = await request(app.getHttpServer())
      .post('/api/v1/devices')
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        deviceModelId,
        imei: `87${imeiSuffix}`,
        serialNumber: `ST-E2E-B-${codeSuffix}`,
        hardwareVersion: '1.0',
        firmwareVersion: '1.0.1',
      })
      .expect(201);

    replacementDeviceId = replacementDeviceResponse.body.id as string;

    await request(app.getHttpServer())
      .post(`/api/v1/devices/${firstDeviceId}/allocate`)
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        dealerOrganizationId: dealerId,
        notes: 'E2E first-device allocation',
      })
      .expect(201);

    await request(app.getHttpServer())
      .post(`/api/v1/devices/${replacementDeviceId}/allocate`)
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        dealerOrganizationId: dealerId,
        notes: 'E2E replacement-device allocation',
      })
      .expect(201);

    const installationResponse = await request(app.getHttpServer())
      .post(`/api/v1/devices/${firstDeviceId}/install`)
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        vehicleId,
        latitude: 23.8103,
        longitude: 90.4125,
        ignitionConnected: true,
        relayConnected: true,
        sosConnected: true,
        powerConnectionType: 'BATTERY_DIRECT',
      })
      .expect(201);

    expect(installationResponse.body.status).toBe('COMPLETED');
    expect(installationResponse.body.assignment.status).toBe('ACTIVE');

    const replacementResponse = await request(app.getHttpServer())
      .post(`/api/v1/devices/${firstDeviceId}/replace`)
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        replacementDeviceId,
        removalReason: 'WARRANTY_REPLACEMENT',
        ignitionConnected: true,
        relayConnected: true,
        sosConnected: true,
        notes: 'E2E replacement',
      })
      .expect(201);

    expect(replacementResponse.body.removed.assignment.status).toBe('ENDED');
    expect(replacementResponse.body.installed.assignment.status).toBe('ACTIVE');

    await request(app.getHttpServer())
      .post(`/api/v1/devices/${replacementDeviceId}/remove`)
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        assignmentEndReason: 'CUSTOMER_REQUEST',
        removalReason: 'CUSTOMER_REQUEST',
        notes: 'E2E final removal',
      })
      .expect(201);

    const historyResponse = await request(app.getHttpServer())
      .get(`/api/v1/vehicles/${vehicleId}/device-history`)
      .set('Authorization', `Bearer ${accessToken}`)
      .expect(200);

    expect(historyResponse.body).toHaveLength(2);
    expect(
      historyResponse.body.every((assignment: { status: string }) => assignment.status === 'ENDED'),
    ).toBe(true);

    const firstAllocated = await prisma.device.findUniqueOrThrow({
      where: {
        id: firstDeviceId,
      },
    });

    const replacementAllocated = await prisma.device.findUniqueOrThrow({
      where: {
        id: replacementDeviceId,
      },
    });

    expect(firstAllocated.lifecycleStatus).toBe('ALLOCATED');
    expect(replacementAllocated.lifecycleStatus).toBe('ALLOCATED');

    await request(app.getHttpServer())
      .post(`/api/v1/devices/${firstDeviceId}/return`)
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        notes: 'E2E first-device return',
      })
      .expect(201);

    await request(app.getHttpServer())
      .post(`/api/v1/devices/${replacementDeviceId}/return`)
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        notes: 'E2E replacement-device return',
      })
      .expect(201);

    const firstReturned = await prisma.device.findUniqueOrThrow({
      where: {
        id: firstDeviceId,
      },
    });

    const replacementReturned = await prisma.device.findUniqueOrThrow({
      where: {
        id: replacementDeviceId,
      },
    });

    expect(firstReturned.lifecycleStatus).toBe('IN_STOCK');
    expect(replacementReturned.lifecycleStatus).toBe('IN_STOCK');
  });
});
