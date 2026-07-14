import type { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import type { TestingModule } from '@nestjs/testing';
import { randomUUID } from 'node:crypto';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { configureApplication } from '../src/bootstrap/app.setup';
import { PrismaService } from '../src/database/prisma.service';
import { PasswordService } from '../src/identity/common/password.service';

describe('Solid Tracker Dealer and Customer Management (e2e)', () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let platformUserId: string;
  let dealerId: string;
  let managerUserId: string;
  let groupId: string;
  let customerId: string;
  let accessToken: string;

  const platformPassword = 'SolidTracker123!';

  beforeAll(async () => {
    const moduleFixture: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    app = moduleFixture.createNestApplication();
    configureApplication(app);
    await app.init();

    prisma = app.get(PrismaService);
    const passwordService = app.get(PasswordService);
    const suffix = randomUUID().replace(/-/g, '').slice(0, 8);
    const digits = suffix.replace(/[a-f]/g, '7');
    const platformMobile = `+88015${digits}`;

    const platformOrganization = await prisma.organization.findUniqueOrThrow({
      where: {
        code: 'ORG-PLATFORM',
      },
    });

    const platformRole = await prisma.role.findUniqueOrThrow({
      where: {
        code: 'PLATFORM_SUPER_ADMIN',
      },
    });

    const platformUser = await prisma.user.create({
      data: {
        userCode: `TEST-${randomUUID().replace(/-/g, '').slice(0, 12).toUpperCase()}`,
        fullName: 'Management E2E Platform User',
        mobileNumber: platformMobile,
        normalizedMobileNumber: platformMobile,
        passwordHash: await passwordService.hash(platformPassword),
        passwordChangedAt: new Date(),
        mobileVerifiedAt: new Date(),
        status: 'ACTIVE',
      },
    });

    platformUserId = platformUser.id;

    const membership = await prisma.organizationMembership.create({
      data: {
        organizationId: platformOrganization.id,
        userId: platformUser.id,
        membershipType: 'EMPLOYEE',
        status: 'ACTIVE',
        joinedAt: new Date(),
      },
    });

    await prisma.roleAssignment.create({
      data: {
        userId: platformUser.id,
        roleId: platformRole.id,
        organizationMembershipId: membership.id,
        scopeType: 'PLATFORM',
        scopeId: platformOrganization.id,
        status: 'ACTIVE',
      },
    });

    const login = await request(app.getHttpServer())
      .post('/api/v1/auth/login')
      .send({
        mobileNumber: platformMobile,
        password: platformPassword,
        platform: 'WEB',
        deviceName: 'Dealer Customer E2E',
        appVersion: 'test',
      })
      .expect(200);

    accessToken = login.body.accessToken as string;
  });

  afterAll(async () => {
    const now = new Date();

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

    if (groupId) {
      await prisma.customerGroup.update({
        where: {
          id: groupId,
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

    for (const userId of [managerUserId, platformUserId]) {
      if (userId) {
        await prisma.userSession.deleteMany({
          where: {
            userId,
          },
        });

        await prisma.user.update({
          where: {
            id: userId,
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

  it('creates a dealer, manager, group, customer, and transfer history', async () => {
    const dealerResponse = await request(app.getHttpServer())
      .post('/api/v1/dealers')
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        name: 'Management E2E Dealer',
        legalName: 'Management E2E Dealer Limited',
        contactMobile: '01700000000',
        commissionEnabled: true,
      })
      .expect(201);

    dealerId = dealerResponse.body.id as string;

    const managerSuffix = randomUUID().replace(/-/g, '').slice(0, 8).replace(/[a-f]/g, '8');

    const managerResponse = await request(app.getHttpServer())
      .post(`/api/v1/dealers/${dealerId}/staff`)
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        fullName: 'Management E2E Dealer Manager',
        mobileNumber: `+88018${managerSuffix}`,
        password: 'DealerManager123!',
        roleCode: 'DEALER_MANAGER',
      })
      .expect(201);

    managerUserId = managerResponse.body.user.id as string;

    const groupResponse = await request(app.getHttpServer())
      .post(`/api/v1/dealers/${dealerId}/customer-groups`)
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        name: 'E2E Fleet Customers',
        description: 'Created by the management E2E suite',
      })
      .expect(201);

    groupId = groupResponse.body.id as string;

    const customerResponse = await request(app.getHttpServer())
      .post('/api/v1/customers/individual')
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        fullName: 'Management E2E Customer',
        managingDealerId: dealerId,
        customerGroupId: groupId,
        primaryMobile: '01900000000',
        billingAddress: {
          city: 'Dhaka',
          country: 'Bangladesh',
        },
      })
      .expect(201);

    customerId = customerResponse.body.id as string;

    expect(customerResponse.body.managingDealerId).toBe(dealerId);
    expect(customerResponse.body.customerGroupId).toBe(groupId);

    const listResponse = await request(app.getHttpServer())
      .get('/api/v1/customers')
      .query({
        managingDealerId: dealerId,
      })
      .set('Authorization', `Bearer ${accessToken}`)
      .expect(200);

    expect(
      listResponse.body.items.some((customer: { id: string }) => customer.id === customerId),
    ).toBe(true);

    const transferResponse = await request(app.getHttpServer())
      .post(`/api/v1/customers/${customerId}/transfer`)
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        targetDealerId: null,
        targetCustomerGroupId: null,
        notes: 'E2E transfer to direct platform management',
      })
      .expect(201);

    expect(transferResponse.body.managingDealerId).toBeNull();
    expect(transferResponse.body.customerGroupId).toBeNull();

    const assignments = await prisma.customerDealerAssignment.findMany({
      where: {
        customerId,
      },
      orderBy: {
        assignedAt: 'asc',
      },
    });

    expect(assignments).toHaveLength(2);
    expect(assignments[0].endedAt).not.toBeNull();
    expect(assignments[1].managementType).toBe('PLATFORM');
  });
});
