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
  | "stopped"
  | "idle"
  | "offline";

export const TRACKING_OFFLINE_AFTER_MS =
  5 * 60 * 1000;

export const TRACKING_MOVING_SPEED_KNOTS =
  1;

export const TRACKING_VEHICLE_STATE_PRESENTATION: Record<
  TrackingVehicleState,
  {
    label: string;
    holderColor: string;
    iconColor: string;
    mapIconUrl: string;
  }
> = {
  moving: {
    label: "Moving",
    holderColor: "#2f9145",
    iconColor: "#ffffff",
    mapIconUrl:
      "/map-vehicles/car-moving.png",
  },
  stopped: {
    label: "Stopped",
    holderColor: "#ff2344",
    iconColor: "#ffffff",
    mapIconUrl:
      "/map-vehicles/car-stopped.png",
  },
  idle: {
    label: "Idle",
    holderColor: "#ffd900",
    iconColor: "#344054",
    mapIconUrl:
      "/map-vehicles/car-idle.png",
  },
  offline: {
    label: "Offline",
    holderColor: "#a6a8ab",
    iconColor: "#ffffff",
    mapIconUrl:
      "/map-vehicles/car-offline.png",
  },
};

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
  position:
    | TrackingLivePosition
    | null
    | undefined,
  now = Date.now(),
): TrackingVehicleState {
  if (!position) {
    return "offline";
  }

  const timestamp =
    position.serverTime ??
    position.fixTime ??
    position.deviceTime ??
    null;

  if (!timestamp) {
    return "offline";
  }

  const timestampMs =
    new Date(timestamp).getTime();

  if (
    !Number.isFinite(timestampMs) ||
    now - timestampMs >
      TRACKING_OFFLINE_AFTER_MS
  ) {
    return "offline";
  }

  const speed =
    typeof position.speed === "number"
      ? position.speed
      : Number(position.speed ?? 0);

  if (
    Number.isFinite(speed) &&
    speed >
      TRACKING_MOVING_SPEED_KNOTS
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

export function trackingVehicleStatePresentation(
  state: TrackingVehicleState,
) {
  return TRACKING_VEHICLE_STATE_PRESENTATION[
    state
  ];
}
