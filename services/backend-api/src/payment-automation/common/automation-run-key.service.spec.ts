import { AutomationRunKeyService } from './automation-run-key.service';

describe('AutomationRunKeyService', () => {
  const service = new AutomationRunKeyService();

  it('returns the same durable key within one interval', () => {
    const first = new Date('2026-07-14T12:00:10.000Z');
    const second = new Date('2026-07-14T12:00:50.000Z');

    expect(service.key(first, 60000)).toBe(service.key(second, 60000));
  });

  it('returns a different key for the next interval', () => {
    const first = new Date('2026-07-14T12:00:10.000Z');
    const second = new Date('2026-07-14T12:01:10.000Z');

    expect(service.key(first, 60000)).not.toBe(service.key(second, 60000));
  });
});
