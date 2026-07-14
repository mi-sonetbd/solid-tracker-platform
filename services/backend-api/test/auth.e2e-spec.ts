import type { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import type { TestingModule } from '@nestjs/testing';
import { randomUUID } from 'node:crypto';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { configureApplication } from '../src/bootstrap/app.setup';
import { PrismaService } from '../src/database/prisma.service';
import { PasswordService } from '../src/identity/common/password.service';

describe('Solid Tracker Authentication (e2e)', () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let testUserId: string;
  let testMobile: string;
  const testPassword = 'SolidTracker123!';

  beforeAll(async () => {
    const moduleFixture: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    app = moduleFixture.createNestApplication();
    configureApplication(app);
    await app.init();

    prisma = app.get(PrismaService);
    const passwordService = app.get(PasswordService);
    const uniqueSuffix = randomUUID().replace(/-/g, '').slice(0, 8);
    testMobile = `+88017${uniqueSuffix.replace(/[a-f]/g, '7')}`;

    const user = await prisma.user.create({
      data: {
        userCode: `TEST-${randomUUID().replace(/-/g, '').slice(0, 12).toUpperCase()}`,
        fullName: 'Authentication E2E User',
        mobileNumber: testMobile,
        normalizedMobileNumber: testMobile,
        passwordHash: await passwordService.hash(testPassword),
        passwordChangedAt: new Date(),
        mobileVerifiedAt: new Date(),
        status: 'ACTIVE',
      },
    });

    testUserId = user.id;
  });

  afterAll(async () => {
    if (testUserId) {
      await prisma.userSession.deleteMany({
        where: { userId: testUserId },
      });

      await prisma.otpChallenge.deleteMany({
        where: { userId: testUserId },
      });

      await prisma.user.update({
        where: { id: testUserId },
        data: {
          status: 'ARCHIVED',
          passwordHash: null,
          archivedAt: new Date(),
        },
      });
    }

    if (app) {
      await app.close();
    }
  });

  it('logs in, rotates refresh token, and revokes the session', async () => {
    const login = await request(app.getHttpServer())
      .post('/api/v1/auth/login')
      .send({
        mobileNumber: testMobile,
        password: testPassword,
        platform: 'WEB',
        deviceName: 'E2E Test',
        appVersion: 'test',
      })
      .expect(200);

    expect(login.body.tokenType).toBe('Bearer');
    expect(login.body.accessToken).toEqual(expect.any(String));
    expect(login.body.refreshToken).toEqual(expect.any(String));

    const me = await request(app.getHttpServer())
      .get('/api/v1/auth/me')
      .set('Authorization', `Bearer ${login.body.accessToken}`)
      .expect(200);

    expect(me.body.userId).toBe(testUserId);
    expect(me.body.permissions).toEqual([]);

    const refreshed = await request(app.getHttpServer())
      .post('/api/v1/auth/refresh')
      .send({
        refreshToken: login.body.refreshToken,
      })
      .expect(200);

    expect(refreshed.body.refreshToken).not.toBe(login.body.refreshToken);

    await request(app.getHttpServer())
      .post('/api/v1/auth/logout')
      .set('Authorization', `Bearer ${refreshed.body.accessToken}`)
      .expect(204);

    await request(app.getHttpServer())
      .get('/api/v1/auth/me')
      .set('Authorization', `Bearer ${refreshed.body.accessToken}`)
      .expect(401);
  });
});
