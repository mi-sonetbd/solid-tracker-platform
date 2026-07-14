import { Injectable } from '@nestjs/common';

interface NormalizedPosition {
  latitude: number;
  longitude: number;
  occurredAt: Date;
  speedKph: number;
  ignition: boolean | null;
}

export interface MobileTripSummary {
  startedAt: string;
  endedAt: string;
  durationSeconds: number;
  distanceKm: number;
  maxSpeedKph: number;
  start: {
    latitude: number;
    longitude: number;
  };
  end: {
    latitude: number;
    longitude: number;
  };
  pointCount: number;
}

@Injectable()
export class MobileTripBuilderService {
  build(input: unknown[]): MobileTripSummary[] {
    const positions = input
      .map((value) => this.normalize(value))
      .filter((value): value is NormalizedPosition => value !== null)
      .sort((left, right) => left.occurredAt.getTime() - right.occurredAt.getTime());
    const trips: MobileTripSummary[] = [];
    let active: NormalizedPosition[] = [];

    for (const position of positions) {
      const moving = position.speedKph >= 2 || position.ignition === true;

      if (moving) {
        active.push(position);
        continue;
      }

      if (active.length > 0) {
        this.finish(active, trips);
        active = [];
      }
    }

    if (active.length > 0) {
      this.finish(active, trips);
    }

    return trips.reverse();
  }

  private normalize(value: unknown): NormalizedPosition | null {
    if (value === null || typeof value !== 'object' || Array.isArray(value)) {
      return null;
    }

    const record = value as Record<string, unknown>;
    const latitude = Number(record.latitude);
    const longitude = Number(record.longitude);
    const dateValue = record.fixTime ?? record.deviceTime ?? record.serverTime;
    const occurredAt = new Date(String(dateValue ?? ''));
    const speedKnots = Number(record.speed ?? 0);
    const attributes =
      record.attributes !== null &&
      typeof record.attributes === 'object' &&
      !Array.isArray(record.attributes)
        ? (record.attributes as Record<string, unknown>)
        : {};
    const ignitionValue = attributes.ignition;

    if (
      !Number.isFinite(latitude) ||
      !Number.isFinite(longitude) ||
      Number.isNaN(occurredAt.getTime())
    ) {
      return null;
    }

    return {
      latitude,
      longitude,
      occurredAt,
      speedKph: Number.isFinite(speedKnots) ? speedKnots * 1.852 : 0,
      ignition: typeof ignitionValue === 'boolean' ? ignitionValue : null,
    };
  }

  private finish(points: NormalizedPosition[], trips: MobileTripSummary[]): void {
    if (points.length === 0) {
      return;
    }

    let distanceKm = 0;
    let maxSpeedKph = 0;

    for (let index = 0; index < points.length; index += 1) {
      maxSpeedKph = Math.max(maxSpeedKph, points[index].speedKph);

      if (index > 0) {
        distanceKm += this.distance(points[index - 1], points[index]);
      }
    }

    const first = points[0];
    const last = points[points.length - 1];

    trips.push({
      startedAt: first.occurredAt.toISOString(),
      endedAt: last.occurredAt.toISOString(),
      durationSeconds: Math.max(
        0,
        Math.round((last.occurredAt.getTime() - first.occurredAt.getTime()) / 1000),
      ),
      distanceKm: Number(distanceKm.toFixed(3)),
      maxSpeedKph: Number(maxSpeedKph.toFixed(1)),
      start: {
        latitude: first.latitude,
        longitude: first.longitude,
      },
      end: {
        latitude: last.latitude,
        longitude: last.longitude,
      },
      pointCount: points.length,
    });
  }

  private distance(left: NormalizedPosition, right: NormalizedPosition): number {
    const radiusKm = 6371;
    const latitudeDelta = this.radians(right.latitude - left.latitude);
    const longitudeDelta = this.radians(right.longitude - left.longitude);
    const leftLatitude = this.radians(left.latitude);
    const rightLatitude = this.radians(right.latitude);
    const calculation =
      Math.sin(latitudeDelta / 2) ** 2 +
      Math.cos(leftLatitude) * Math.cos(rightLatitude) * Math.sin(longitudeDelta / 2) ** 2;

    return radiusKm * 2 * Math.atan2(Math.sqrt(calculation), Math.sqrt(1 - calculation));
  }

  private radians(value: number): number {
    return (value * Math.PI) / 180;
  }
}
