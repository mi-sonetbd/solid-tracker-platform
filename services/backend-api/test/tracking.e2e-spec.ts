import type { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import type { TestingModule } from '@nestjs/testing';
import { createServer, type IncomingMessage, type Server, type ServerResponse } from 'node:http';
import type { AddressInfo } from 'node:net';
import { randomInt, randomUUID } from 'node:crypto';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { configureApplication } from '../src/bootstrap/app.setup';
import { PrismaService } from '../src/database/prisma.service';
import { PasswordService } from '../src/identity/common/password.service';

interface FakeDevice {
  id: number;
  name: string;
  uniqueId: string;
  disabled?: boolean;
  category?: string;
  attributes?: Record<string, unknown>;
}

interface FakeGeofence {
  id: number;
  name: string;
  description?: string;
  area: string;
  attributes?: Record<string, unknown>;
}

describe('Tracking and Traccar integration lifecycle (e2e)', () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let fakeTraccar: Server;
  let fakeTraccarBaseUrl: string;
  let accessToken: string;
  let platformUserId: string;
  let platformMembershipId: string;
  let platformRoleAssignmentId: string;
  let dealerId: string;
  let customerId: string;
  let vehicleId: string;
  let deviceModelId: string;
  let deviceId: string;
  let traccarServerId: string;
  let geofenceId: string;
  let notificationRuleId: string;
  let trackingEventId: string;

  const fakeDevices: FakeDevice[] = [];
  const fakeGeofences: FakeGeofence[] = [];
  let nextDeviceId = 101;
  let nextGeofenceId = 201;
  let nextCommandId = 301;

  const numericSuffix = randomInt(10_000_000, 100_000_000).toString();
  const codeSuffix = randomUUID().replace(/-/g, '').slice(0, 10).toUpperCase();
  const mobileNumber = `+88018${numericSuffix}`;
  const password = 'SolidTrackerTest123';
  const imei = `86${Date.now().toString().slice(-13).padStart(13, '0')}`;

  beforeAll(async () => {
    fakeTraccar = createServer((incoming: IncomingMessage, outgoing: ServerResponse) => {
      void handleFakeTraccar(incoming, outgoing);
    });

    await new Promise<void>((resolve, reject) => {
      fakeTraccar.once('error', reject);
      fakeTraccar.listen(0, '127.0.0.1', () => {
        fakeTraccar.off('error', reject);
        resolve();
      });
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
        userCode: `USR-TRK-${codeSuffix}`,
        fullName: 'Tracking E2E Administrator',
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

    const roleAssignment = await prisma.roleAssignment.create({
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

    platformRoleAssignmentId = roleAssignment.id;

    const loginResponse = await request(app.getHttpServer())
      .post('/api/v1/auth/login')
      .send({
        mobileNumber,
        password,
        platform: 'WEB',
        deviceName: 'Tracking E2E',
        appVersion: 'test',
      })
      .expect(200);

    accessToken = loginResponse.body.accessToken as string;
  });

  afterAll(async () => {
    const now = new Date();

    if (prisma) {
      if (notificationRuleId) {
        await prisma.notificationRule.updateMany({
          where: {
            id: notificationRuleId,
          },
          data: {
            enabled: false,
            archivedAt: now,
          },
        });
      }

      if (geofenceId) {
        await prisma.vehicleGeofenceAssignment.updateMany({
          where: {
            geofenceId,
            status: 'ACTIVE',
          },
          data: {
            status: 'ENDED',
            activeUntil: now,
          },
        });

        await prisma.geofence.updateMany({
          where: {
            id: geofenceId,
          },
          data: {
            status: 'ARCHIVED',
            archivedAt: now,
            syncStatus: 'DISABLED',
          },
        });
      }

      if (deviceId) {
        await prisma.traccarDeviceMapping.updateMany({
          where: {
            deviceId,
          },
          data: {
            isActive: false,
            isPrimary: false,
            syncStatus: 'DISABLED',
            disabledAt: now,
          },
        });

        await prisma.vehicleDeviceAssignment.updateMany({
          where: {
            deviceId,
            status: 'ACTIVE',
          },
          data: {
            status: 'ENDED',
            endedAt: now,
            endReason: 'OTHER',
            endNotes: 'Tracking E2E cleanup',
            endedByUserId: platformUserId,
          },
        });

        await prisma.deviceInstallation.updateMany({
          where: {
            deviceId,
            status: {
              in: ['SCHEDULED', 'IN_PROGRESS', 'COMPLETED'],
            },
          },
          data: {
            status: 'REMOVED',
            removedAt: now,
            removalReason: 'OTHER',
          },
        });

        await prisma.device.updateMany({
          where: {
            id: deviceId,
          },
          data: {
            lifecycleStatus: 'RETIRED',
            retiredAt: now,
          },
        });
      }

      if (traccarServerId) {
        await prisma.traccarServer.updateMany({
          where: {
            id: traccarServerId,
          },
          data: {
            isDefault: false,
            status: 'ARCHIVED',
            archivedAt: now,
          },
        });
      }

      if (deviceModelId) {
        await prisma.deviceModel.updateMany({
          where: {
            id: deviceModelId,
          },
          data: {
            status: 'ARCHIVED',
            archivedAt: now,
          },
        });
      }

      if (vehicleId) {
        await prisma.vehicle.updateMany({
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
        await prisma.customer.updateMany({
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
        await prisma.organization.updateMany({
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

    if (fakeTraccar) {
      await new Promise<void>((resolve, reject) => {
        fakeTraccar.close((error) => {
          if (error) {
            reject(error);
          } else {
            resolve();
          }
        });
      });
    }
  });

  it('synchronizes tracking, positions, events, geofences, notifications, commands, and jobs', async () => {
    const dealerResponse = await request(app.getHttpServer())
      .post('/api/v1/dealers')
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        name: `Tracking E2E Dealer ${codeSuffix}`,
        contactMobile: `017${numericSuffix}`,
      })
      .expect(201);

    dealerId = dealerResponse.body.id as string;

    const customerResponse = await request(app.getHttpServer())
      .post('/api/v1/customers/individual')
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        managingDealerId: dealerId,
        fullName: `Tracking E2E Customer ${codeSuffix}`,
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
        registrationNumber: `DHAKA-TRK-${codeSuffix}`,
        manufacturer: 'Solid Tracker Test',
        modelName: 'Tracking Lifecycle Car',
        manufacturingYear: 2026,
      })
      .expect(201);

    vehicleId = vehicleResponse.body.id as string;

    const modelResponse = await request(app.getHttpServer())
      .post('/api/v1/device-models')
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        manufacturer: `Tracking E2E ${codeSuffix}`,
        modelName: 'ST-TRACK-100',
        protocol: 'osmand',
        networkType: 'LTE_4G',
        capabilities: {
          ignition: true,
          relay: true,
          commands: true,
        },
      })
      .expect(201);

    deviceModelId = modelResponse.body.id as string;

    const deviceResponse = await request(app.getHttpServer())
      .post('/api/v1/devices')
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        deviceModelId,
        imei,
        serialNumber: `ST-TRK-${codeSuffix}`,
        hardwareVersion: '1.0',
        firmwareVersion: '1.0.0',
      })
      .expect(201);

    deviceId = deviceResponse.body.id as string;

    await request(app.getHttpServer())
      .post(`/api/v1/devices/${deviceId}/allocate`)
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        dealerOrganizationId: dealerId,
        notes: 'Tracking E2E allocation',
      })
      .expect(201);

    await request(app.getHttpServer())
      .post(`/api/v1/devices/${deviceId}/install`)
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        vehicleId,
        latitude: 23.8103,
        longitude: 90.4125,
        ignitionConnected: true,
        relayConnected: true,
        powerConnectionType: 'BATTERY_DIRECT',
      })
      .expect(201);

    const serverResponse = await request(app.getHttpServer())
      .post('/api/v1/tracking/traccar-servers')
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        name: `Fake Traccar ${codeSuffix}`,
        baseUrl: fakeTraccarBaseUrl,
        username: 'tracking-api',
        password: 'tracking-secret',
        isDefault: true,
      })
      .expect(201);

    traccarServerId = serverResponse.body.id as string;
    const serverCode = serverResponse.body.serverCode as string;

    await request(app.getHttpServer())
      .post(`/api/v1/tracking/traccar-servers/${traccarServerId}/health-check`)
      .set('Authorization', `Bearer ${accessToken}`)
      .expect(201);

    const syncResponse = await request(app.getHttpServer())
      .post(`/api/v1/tracking/devices/${deviceId}/sync`)
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        serverId: traccarServerId,
      })
      .expect(201);

    expect(syncResponse.body.mapping.syncStatus).toBe('SYNCED');
    expect(syncResponse.body.mapping.traccarDeviceId).toBe('101');

    const liveResponse = await request(app.getHttpServer())
      .get(`/api/v1/tracking/vehicles/${vehicleId}/live-position`)
      .set('Authorization', `Bearer ${accessToken}`)
      .expect(200);

    expect(liveResponse.body.position.latitude).toBe(23.8103);
    expect(liveResponse.body.position.longitude).toBe(90.4125);

    const geofenceResponse = await request(app.getHttpServer())
      .post('/api/v1/tracking/geofences')
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        customerId,
        name: `E2E Safe Zone ${codeSuffix}`,
        geometryType: 'CIRCLE',
        geometryData: {
          center: {
            latitude: 23.8103,
            longitude: 90.4125,
          },
          radius: 500,
        },
        status: 'ACTIVE',
      })
      .expect(201);

    geofenceId = geofenceResponse.body.id as string;

    const geofenceSyncResponse = await request(app.getHttpServer())
      .post(`/api/v1/tracking/geofences/${geofenceId}/sync`)
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        serverId: traccarServerId,
      })
      .expect(201);

    expect(geofenceSyncResponse.body.geofence.syncStatus).toBe('SYNCED');

    await request(app.getHttpServer())
      .post(`/api/v1/tracking/geofences/${geofenceId}/assignments`)
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        vehicleId,
        monitorEntry: true,
        monitorExit: true,
      })
      .expect(201);

    const ruleResponse = await request(app.getHttpServer())
      .post('/api/v1/tracking/notification-rules')
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        customerId,
        vehicleId,
        eventType: 'deviceOverspeed',
        minimumSeverity: 'WARNING',
        channel: 'IN_APP',
        recipientType: 'CUSTOM_ADDRESS',
        recipientAddress: `in-app:e2e:${codeSuffix}`,
        enabled: true,
        cooldownSeconds: 0,
        dailyLimit: 10,
      })
      .expect(201);

    notificationRuleId = ruleResponse.body.id as string;

    const eventTime = new Date().toISOString();
    const webhookSecret = process.env.TRACKING_WEBHOOK_SECRET;

    if (!webhookSecret) {
      throw new Error('TRACKING_WEBHOOK_SECRET is required for tracking E2E.');
    }

    const webhookResponse = await request(app.getHttpServer())
      .post(`/api/v1/tracking/webhooks/traccar/${serverCode}`)
      .set('X-Tracking-Webhook-Secret', webhookSecret)
      .send({
        event: {
          id: 7001,
          type: 'deviceOverspeed',
          eventTime,
          deviceId: 101,
          attributes: {
            speedLimit: 60,
          },
        },
        device: {
          id: 101,
          uniqueId: imei,
          name: `DHAKA-TRK-${codeSuffix}`,
        },
        position: {
          id: 5001,
          deviceId: 101,
          fixTime: eventTime,
          latitude: 23.8103,
          longitude: 90.4125,
          speed: 80,
          attributes: {
            ignition: true,
          },
        },
      })
      .expect(201);

    expect(webhookResponse.body.duplicate).toBe(false);
    expect(webhookResponse.body.event.severity).toBe('WARNING');
    expect(webhookResponse.body.notifications).toHaveLength(1);

    trackingEventId = webhookResponse.body.event.id as string;

    const statusWebhookResponse = await request(app.getHttpServer())
      .post(`/api/v1/tracking/webhooks/traccar/${serverCode}`)
      .set('X-Tracking-Webhook-Secret', webhookSecret)
      .send({
        event: {
          id: 7002,
          type: 'deviceOnline',
          eventTime,
          deviceId: 101,
        },
        device: {
          id: 101,
          uniqueId: imei,
          name: `DHAKA-TRK-${codeSuffix}`,
        },
      })
      .expect(201);

    expect(statusWebhookResponse.body.duplicate).toBe(false);
    expect(statusWebhookResponse.body.event.eventType).toBe('deviceOnline');
    expect(statusWebhookResponse.body.event.latitude).toBeNull();
    expect(statusWebhookResponse.body.event.longitude).toBeNull();

    const eventListResponse = await request(app.getHttpServer())
      .get(`/api/v1/tracking/events?vehicleId=${vehicleId}`)
      .set('Authorization', `Bearer ${accessToken}`)
      .expect(200);

    expect(eventListResponse.body.total).toBeGreaterThanOrEqual(1);

    const acknowledgedResponse = await request(app.getHttpServer())
      .post(`/api/v1/tracking/events/${trackingEventId}/acknowledge`)
      .set('Authorization', `Bearer ${accessToken}`)
      .expect(201);

    expect(acknowledgedResponse.body.acknowledgedAt).toBeTruthy();

    const notificationsResponse = await request(app.getHttpServer())
      .get(`/api/v1/tracking/notifications?trackingEventId=${trackingEventId}`)
      .set('Authorization', `Bearer ${accessToken}`)
      .expect(200);

    expect(notificationsResponse.body.total).toBe(1);
    expect(notificationsResponse.body.items[0].status).toBe('QUEUED');

    const commandResponse = await request(app.getHttpServer())
      .post('/api/v1/tracking/commands')
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        deviceId,
        vehicleId,
        commandType: 'REQUEST_POSITION',
        parameters: {},
        reason: 'Tracking E2E position request',
      })
      .expect(201);

    expect(commandResponse.body.status).toBe('COMPLETED');
    expect(commandResponse.body.traccarCommandId).toBe('301');

    const jobsResponse = await request(app.getHttpServer())
      .get('/api/v1/tracking/integration-jobs')
      .set('Authorization', `Bearer ${accessToken}`)
      .expect(200);

    expect(jobsResponse.body.total).toBeGreaterThanOrEqual(5);

    await request(app.getHttpServer())
      .post(`/api/v1/tracking/geofences/${geofenceId}/assignments/${vehicleId}/end`)
      .set('Authorization', `Bearer ${accessToken}`)
      .expect(201);
  });

  async function handleFakeTraccar(
    incoming: IncomingMessage,
    outgoing: ServerResponse,
  ): Promise<void> {
    const url = new URL(incoming.url ?? '/', fakeTraccarBaseUrl || 'http://127.0.0.1');
    const method = incoming.method ?? 'GET';

    if (!incoming.headers.authorization) {
      respond(outgoing, 401, {
        message: 'Authorization required',
      });
      return;
    }

    if (method === 'GET' && url.pathname === '/api/server') {
      respond(outgoing, 200, {
        id: 1,
        version: '6.14.5-test',
        registration: false,
        readonly: false,
      });
      return;
    }

    if (method === 'GET' && url.pathname === '/api/devices') {
      const uniqueId = url.searchParams.get('uniqueId');
      respond(
        outgoing,
        200,
        uniqueId ? fakeDevices.filter((device) => device.uniqueId === uniqueId) : fakeDevices,
      );
      return;
    }

    if (method === 'POST' && url.pathname === '/api/devices') {
      const body = (await readJson(incoming)) as Omit<FakeDevice, 'id'>;
      const device: FakeDevice = {
        ...body,
        id: nextDeviceId++,
      };

      fakeDevices.push(device);
      respond(outgoing, 200, device);
      return;
    }

    if (method === 'PUT' && /^\/api\/devices\/\d+$/.test(url.pathname)) {
      const id = Number(url.pathname.split('/').at(-1));
      const body = (await readJson(incoming)) as FakeDevice;
      const index = fakeDevices.findIndex((device) => device.id === id);
      const device = {
        ...body,
        id,
      };

      if (index >= 0) {
        fakeDevices[index] = device;
      } else {
        fakeDevices.push(device);
      }

      respond(outgoing, 200, device);
      return;
    }

    if (method === 'GET' && url.pathname === '/api/positions') {
      respond(outgoing, 200, [
        {
          id: 5001,
          deviceId: 101,
          protocol: 'osmand',
          serverTime: new Date().toISOString(),
          deviceTime: new Date().toISOString(),
          fixTime: new Date().toISOString(),
          valid: true,
          latitude: 23.8103,
          longitude: 90.4125,
          altitude: 8,
          speed: 25,
          course: 180,
          accuracy: 5,
          attributes: {
            ignition: true,
          },
        },
      ]);
      return;
    }

    if (method === 'POST' && url.pathname === '/api/geofences') {
      const body = (await readJson(incoming)) as Omit<FakeGeofence, 'id'>;
      const geofence: FakeGeofence = {
        ...body,
        id: nextGeofenceId++,
      };

      fakeGeofences.push(geofence);
      respond(outgoing, 200, geofence);
      return;
    }

    if (method === 'PUT' && /^\/api\/geofences\/\d+$/.test(url.pathname)) {
      const id = Number(url.pathname.split('/').at(-1));
      const body = (await readJson(incoming)) as FakeGeofence;
      const index = fakeGeofences.findIndex((geofence) => geofence.id === id);
      const geofence = {
        ...body,
        id,
      };

      if (index >= 0) {
        fakeGeofences[index] = geofence;
      } else {
        fakeGeofences.push(geofence);
      }

      respond(outgoing, 200, geofence);
      return;
    }

    if (['POST', 'DELETE'].includes(method) && url.pathname === '/api/permissions') {
      await readJson(incoming);
      outgoing.statusCode = 204;
      outgoing.end();
      return;
    }

    if (method === 'POST' && url.pathname === '/api/commands/send') {
      const body = (await readJson(incoming)) as {
        deviceId: number;
        type: string;
        attributes?: Record<string, unknown>;
      };
      const command = {
        id: nextCommandId++,
        ...body,
      };

      respond(outgoing, 200, command);
      return;
    }

    respond(outgoing, 404, {
      message: `${method} ${url.pathname} not implemented`,
    });
  }

  async function readJson(incoming: IncomingMessage): Promise<unknown> {
    const chunks: Buffer[] = [];

    for await (const chunk of incoming) {
      chunks.push(Buffer.from(chunk));
    }

    if (chunks.length === 0) {
      return {};
    }

    return JSON.parse(Buffer.concat(chunks).toString('utf8')) as unknown;
  }

  function respond(outgoing: ServerResponse, status: number, body: unknown): void {
    outgoing.statusCode = status;
    outgoing.setHeader('Content-Type', 'application/json');
    outgoing.end(JSON.stringify(body));
  }
});
