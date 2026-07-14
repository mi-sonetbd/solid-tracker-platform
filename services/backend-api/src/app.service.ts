import { Injectable } from '@nestjs/common';

@Injectable()
export class AppService {
  getServiceInformation() {
    return {
      name: 'Solid Tracker Backend API',
      version: '0.1.0',
      status: 'running',
      documentation: '/docs',
      health: {
        liveness: '/api/v1/health/live',
        readiness: '/api/v1/health/ready',
      },
    };
  }
}
