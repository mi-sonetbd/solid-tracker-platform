import { AppService } from './app.service';

describe('AppService', () => {
  it('returns Solid Tracker service information', () => {
    const service = new AppService();
    const result = service.getServiceInformation();

    expect(result.name).toBe('Solid Tracker Backend API');
    expect(result.status).toBe('running');
    expect(result.health.readiness).toBe('/api/v1/health/ready');
  });
});
