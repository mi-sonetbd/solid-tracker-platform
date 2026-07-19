"use client";

import {
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from "react";
import {
  resolveTrackingVehicleState,
  trackingVehicleStatePresentation,
  type TrackingLivePosition,
  type TrackingLivePositionResponse,
  type TrackingVehicleState,
} from "@/lib/tracking/live-position-types";

type RuntimeScope =
  | "customer"
  | "management";

export type VehicleRuntimeView = {
  state: TrackingVehicleState;
  label: string;
  holderColor: string;
  iconColor: string;
  shadow: string;
  position:
    TrackingLivePosition | null;
};

type VehicleRuntimeProps = {
  scope: RuntimeScope;
  vehicleId: string;
  hasTracker: boolean;
  children: (
    runtime: VehicleRuntimeView,
  ) => ReactNode;
};

const PANEL_POLL_INTERVAL_MS =
  30 * 1000;

async function readPosition(
  scope: RuntimeScope,
  vehicleId: string,
  signal: AbortSignal,
) {
  const response = await fetch(
    `/api/${scope}/vehicles/${encodeURIComponent(
      vehicleId,
    )}/live-position`,
    {
      cache: "no-store",
      signal,
    },
  );

  if (!response.ok) {
    return null;
  }

  const payload =
    (await response.json()) as
      TrackingLivePositionResponse;

  return payload.position ?? null;
}

export function VehicleRuntime({
  scope,
  vehicleId,
  hasTracker,
  children,
}: VehicleRuntimeProps) {
  const [position, setPosition] =
    useState<
      TrackingLivePosition | null
    >(null);
  const [clock, setClock] =
    useState(() => Date.now());

  useEffect(() => {
    if (!hasTracker) {
      return;
    }

    let active = true;
    let requestController:
      AbortController | null = null;

    const refresh = async () => {
      requestController?.abort();
      requestController =
        new AbortController();

      try {
        const nextPosition =
          await readPosition(
            scope,
            vehicleId,
            requestController.signal,
          );

        if (!active) return;

        setPosition(nextPosition);
        setClock(Date.now());
      }
      catch (error) {
        if (
          error instanceof DOMException &&
          error.name === "AbortError"
        ) {
          return;
        }

        if (active) {
          setClock(Date.now());
        }
      }
    };

    void refresh();

    const interval =
      window.setInterval(
        () => {
          void refresh();
        },
        PANEL_POLL_INTERVAL_MS,
      );

    return () => {
      active = false;
      requestController?.abort();
      window.clearInterval(interval);
    };
  }, [
    hasTracker,
    scope,
    vehicleId,
  ]);

  useEffect(() => {
    const interval =
      window.setInterval(
        () => setClock(Date.now()),
        PANEL_POLL_INTERVAL_MS,
      );

    return () =>
      window.clearInterval(interval);
  }, []);

  const runtime =
    useMemo<VehicleRuntimeView>(() => {
      const state = hasTracker
        ? resolveTrackingVehicleState(
            position,
            clock,
          )
        : "offline";
      const presentation =
        trackingVehicleStatePresentation(
          state,
        );

      return {
        state,
        label: hasTracker
          ? presentation.label
          : "No tracker",
        holderColor:
          presentation.holderColor,
        iconColor:
          presentation.iconColor,
        shadow:
          "0 2px 7px rgba(52, 75, 114, 0.20)",
        position,
      };
    }, [
      clock,
      hasTracker,
      position,
    ]);

  return <>{children(runtime)}</>;
}
