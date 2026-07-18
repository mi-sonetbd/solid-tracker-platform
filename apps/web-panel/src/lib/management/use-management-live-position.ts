"use client";

import { useEffect, useState } from "react";
import type {
  TrackingLivePosition,
  TrackingLivePositionResponse,
} from "@/lib/tracking/live-position-types";

type Input = {
  vehicleId: string | null;
  enabled: boolean;
  intervalMs?: number;
};

export function useManagementLivePosition({
  vehicleId,
  enabled,
  intervalMs = 8000,
}: Input) {
  const [position, setPosition] = useState<TrackingLivePosition | null>(null);
  const [positionVehicleId, setPositionVehicleId] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");

  useEffect(() => {
    if (!enabled || !vehicleId) {
      return;
    }

    const activeVehicleId = vehicleId;
    const controller = new AbortController();
    let timer: ReturnType<typeof setTimeout> | null = null;

    async function load() {
      setLoading(true);

      try {
        const response = await fetch(
          `/api/management/vehicles/${encodeURIComponent(activeVehicleId)}/live-position`,
          { cache: "no-store", signal: controller.signal },
        );
        const payload = (await response.json()) as
          | TrackingLivePositionResponse
          | { message?: string };

        if (!response.ok) {
          throw new Error(
            "message" in payload && payload.message
              ? payload.message
              : "Live position could not be loaded.",
          );
        }

        setPosition((payload as TrackingLivePositionResponse).position);
        setPositionVehicleId(activeVehicleId);
        setError("");
      } catch (requestError) {
        if (controller.signal.aborted) return;
        setPosition(null);
        setPositionVehicleId(activeVehicleId);
        setError(
          requestError instanceof Error
            ? requestError.message
            : "Live position could not be loaded.",
        );
      } finally {
        if (!controller.signal.aborted) {
          setLoading(false);
          timer = setTimeout(load, intervalMs);
        }
      }
    }

    void load();

    return () => {
      controller.abort();
      if (timer) clearTimeout(timer);
    };
  }, [enabled, intervalMs, vehicleId]);

  const current =
    enabled &&
    Boolean(vehicleId) &&
    positionVehicleId === vehicleId;

  return {
    position: current ? position : null,
    loading:
      enabled && vehicleId
        ? current
          ? loading
          : true
        : false,
    error: current ? error : "",
  };
}