export type TrackingLivePosition = {
  id?: number | string;
  deviceId?: number | string;
  protocol?: string | null;
  serverTime?: string | null;
  deviceTime?: string | null;
  fixTime?: string | null;
  valid?: boolean;
  latitude: number;
  longitude: number;
  altitude?: number | null;
  speed?: number | null;
  course?: number | null;
  address?: string | null;
  accuracy?: number | null;
  attributes?: Record<string, unknown> | null;
};

export type TrackingLivePositionResponse = {
  vehicleId: string;
  deviceId: string;
  mappingId: string;
  traccarServerId: string;
  position: TrackingLivePosition | null;
};

export type TrackingVehicleState =
  | "moving"
  | "idle"
  | "stopped"
  | "offline";

export const TRACKING_OFFLINE_AFTER_MS =
  10 * 60 * 1000;

function trackingBoolean(
  value: unknown,
): boolean | null {
  if (
    value === true ||
    value === 1 ||
    value === "1" ||
    value === "true" ||
    value === "on"
  ) {
    return true;
  }

  if (
    value === false ||
    value === 0 ||
    value === "0" ||
    value === "false" ||
    value === "off"
  ) {
    return false;
  }

  return null;
}

export function resolveTrackingVehicleState(
  position: TrackingLivePosition,
  now = Date.now(),
): TrackingVehicleState {
  const timestamp =
    position.serverTime ??
    position.fixTime ??
    position.deviceTime ??
    null;

  if (timestamp) {
    const time = new Date(timestamp).getTime();

    if (
      Number.isFinite(time) &&
      now - time > TRACKING_OFFLINE_AFTER_MS
    ) {
      return "offline";
    }
  }

  const speed =
    typeof position.speed === "number"
      ? position.speed
      : Number(position.speed ?? 0);

  if (
    Number.isFinite(speed) &&
    speed > 1
  ) {
    return "moving";
  }

  const ignition =
    trackingBoolean(
      position.attributes?.ignition,
    );

  if (ignition === true) {
    return "idle";
  }

  return "stopped";
}
