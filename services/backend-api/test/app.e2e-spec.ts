import { INestApplication } from '@nestjs/common';
import { Test, TestingModule } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { configureApplication } from '../src/bootstrap/app.setup';

describe('Solid Tracker API (e2e)', () => {
  let app: INestApplication;

  beforeAll(async () => {
    const moduleFixture: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    app = moduleFixture.createNestApplication();
    configureApplication(app);
    await app.init();
  });

  afterAll(async () => {
    if (app) {
      await app.close();
    }
  });

  it('GET /api/v1', async () => {
    const response = await request(app.getHttpServer()).get('/api/v1').expect(200);

    expect(response.body.name).toBe('Solid Tracker Backend API');
  });

  it('GET /api/v1/health/live', async () => {
    const response = await request(app.getHttpServer()).get('/api/v1/health/live').expect(200);

    expect(response.body.status).toBe('ok');
  });

  it('GET /api/v1/health/ready', async () => {
    const response = await request(app.getHttpServer()).get('/api/v1/health/ready').expect(200);

    expect(response.body.status).toBe('ok');
    expect(response.body.info.postgresql.status).toBe('up');
    expect(response.body.info.redis.status).toBe('up');
  });
});
