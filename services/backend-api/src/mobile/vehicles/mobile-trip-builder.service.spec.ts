import { MobileTripBuilderService } from './mobile-trip-builder.service';

describe('MobileTripBuilderService', () => {
  const service = new MobileTripBuilderService();

  it('builds a trip from moving Traccar positions', () => {
    const trips = service.build([
      {
        fixTime: '2026-07-14T10:00:00.000Z',
        latitude: 23.81,
        longitude: 90.41,
        speed: 10,
        attributes: { ignition: true },
      },
      {
        fixTime: '2026-07-14T10:05:00.000Z',
        latitude: 23.82,
        longitude: 90.42,
        speed: 15,
        attributes: { ignition: true },
      },
      {
        fixTime: '2026-07-14T10:06:00.000Z',
        latitude: 23.82,
        longitude: 90.42,
        speed: 0,
        attributes: { ignition: false },
      },
    ]);

    expect(trips).toHaveLength(1);
    expect(trips[0].pointCount).toBe(2);
    expect(trips[0].durationSeconds).toBe(300);
    expect(trips[0].distanceKm).toBeGreaterThan(0);
  });
});
