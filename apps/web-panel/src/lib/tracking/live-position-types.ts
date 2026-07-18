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