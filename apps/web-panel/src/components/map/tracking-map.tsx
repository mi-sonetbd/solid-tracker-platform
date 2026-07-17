"use client";

import {
  importLibrary,
  setOptions,
} from "@googlemaps/js-api-loader";
import {
  useCallback,
  useEffect,
  useRef,
  useState,
} from "react";
import type {
  TrackingMapBasemap,
  TrackingMapPosition,
} from "@/components/map/tracking-map-types";

type TrackingMapProps = {
  selectedPosition?: TrackingMapPosition | null;
  basemap?: TrackingMapBasemap;
};

type MapLoadState =
  | "loading"
  | "ready"
  | "error";

declare global {
  interface Window {
    __solidTrackerGoogleMapsConfigured?: boolean;
  }
}

const defaultCenter: google.maps.LatLngLiteral = {
  lat: 20,
  lng: 0,
};

function configureGoogleMaps(apiKey: string) {
  if (
    window.__solidTrackerGoogleMapsConfigured
  ) {
    return;
  }

  setOptions({
    key: apiKey,
    v: "weekly",
  });

  window.__solidTrackerGoogleMapsConfigured =
    true;
}

function mapTypeForBasemap(
  basemap: TrackingMapBasemap,
) {
  return basemap === "satellite"
    ? google.maps.MapTypeId.SATELLITE
    : google.maps.MapTypeId.ROADMAP;
}

export default function TrackingMap({
  selectedPosition = null,
  basemap = "map",
}: TrackingMapProps) {
  const containerRef =
    useRef<HTMLDivElement | null>(null);
  const mapRef =
    useRef<google.maps.Map | null>(null);
  const positionCircleRef =
    useRef<google.maps.Circle | null>(null);
  const positionClickListenerRef =
    useRef<google.maps.MapsEventListener | null>(
      null,
    );
  const infoWindowRef =
    useRef<google.maps.InfoWindow | null>(null);
  const apiKey =
    process.env
      .NEXT_PUBLIC_GOOGLE_MAPS_API_KEY
      ?.trim();
  const [loadState, setLoadState] =
    useState<MapLoadState>(
      apiKey ? "loading" : "error",
    );
  const [loadError, setLoadError] =
    useState(
      apiKey
        ? ""
        : "Google Maps API key is not configured.",
    );

  const clearPositionOverlay =
    useCallback(() => {
      positionClickListenerRef.current?.remove();
      positionClickListenerRef.current = null;

      positionCircleRef.current?.setMap(null);
      positionCircleRef.current = null;

      infoWindowRef.current?.close();
      infoWindowRef.current = null;
    }, []);

  useEffect(() => {
    const container = containerRef.current;

    if (!container) {
      return;
    }

    if (!apiKey) {
      return;
    }

    const googleMapsApiKey = apiKey;
    const mapContainer = container;

    let disposed = false;
    let resizeFrame: number | null = null;
    let resizeObserver: ResizeObserver | null =
      null;

    async function initializeMap() {
      try {
        configureGoogleMaps(googleMapsApiKey);
        await importLibrary("maps");

        if (disposed || !mapContainer.isConnected) {
          return;
        }

        const map = new google.maps.Map(
          mapContainer,
          {
            center: defaultCenter,
            zoom: 2,
            minZoom: 2,
            mapTypeId:
              google.maps.MapTypeId.ROADMAP,
            mapTypeControl: false,
            streetViewControl: false,
            fullscreenControl: false,
            zoomControl: false,
            clickableIcons: false,
            gestureHandling: "greedy",
            keyboardShortcuts: true,
            backgroundColor: "#a9d5df",
          },
        );

        mapRef.current = map;

        resizeObserver = new ResizeObserver(
          () => {
            if (
              disposed ||
              mapRef.current !== map
            ) {
              return;
            }

            if (resizeFrame !== null) {
              cancelAnimationFrame(resizeFrame);
            }

            const center = map.getCenter();

            resizeFrame = requestAnimationFrame(
              () => {
                if (
                  disposed ||
                  mapRef.current !== map
                ) {
                  return;
                }

                google.maps.event.trigger(
                  map,
                  "resize",
                );

                if (center) {
                  map.setCenter(center);
                }
              },
            );
          },
        );

        resizeObserver.observe(mapContainer);

        setLoadError("");
        setLoadState("ready");
      } catch (error: unknown) {
        if (disposed) {
          return;
        }

        mapRef.current = null;
        setLoadState("error");
        setLoadError(
          error instanceof Error
            ? error.message
            : "Google Maps could not load.",
        );
      }
    }

    void initializeMap();

    return () => {
      disposed = true;

      if (resizeFrame !== null) {
        cancelAnimationFrame(resizeFrame);
      }

      resizeObserver?.disconnect();
      clearPositionOverlay();

      if (mapRef.current) {
        google.maps.event.clearInstanceListeners(
          mapRef.current,
        );
      }

      mapRef.current = null;
    };
  }, [
    apiKey,
    clearPositionOverlay,
  ]);

  useEffect(() => {
    const map = mapRef.current;

    if (!map || loadState !== "ready") {
      return;
    }

    map.setMapTypeId(
      mapTypeForBasemap(basemap),
    );
  }, [basemap, loadState]);

  useEffect(() => {
    const map = mapRef.current;

    clearPositionOverlay();

    if (
      !map ||
      loadState !== "ready" ||
      !selectedPosition
    ) {
      return;
    }

    const position:
      google.maps.LatLngLiteral = {
        lat: selectedPosition.latitude,
        lng: selectedPosition.longitude,
      };

    map.setCenter(position);
    map.setZoom(16);

    const circle = new google.maps.Circle({
      map,
      center: position,
      radius: 12,
      strokeColor: "#ffffff",
      strokeOpacity: 1,
      strokeWeight: 3,
      fillColor: "#ff3152",
      fillOpacity: 1,
      clickable: true,
      zIndex: 1000,
    });

    const content =
      document.createElement("div");

    content.className =
      "px-1 py-0.5 text-xs font-semibold text-[#344b72]";
    content.textContent =
      selectedPosition.label;

    const infoWindow =
      new google.maps.InfoWindow({
        content,
        position,
        disableAutoPan: false,
      });

    const clickListener = circle.addListener(
      "click",
      () => {
        infoWindow.open({
          map,
          shouldFocus: false,
        });
      },
    );

    positionCircleRef.current = circle;
    infoWindowRef.current = infoWindow;
    positionClickListenerRef.current =
      clickListener;

    return clearPositionOverlay;
  }, [
    clearPositionOverlay,
    loadState,
    selectedPosition,
  ]);

  function changeZoom(delta: number) {
    const map = mapRef.current;

    if (!map) {
      return;
    }

    const currentZoom = map.getZoom() ?? 2;
    const nextZoom = Math.max(
      2,
      Math.min(21, currentZoom + delta),
    );

    map.setZoom(nextZoom);
  }

  return (
    <div className="relative h-full w-full bg-[#a9d5df]">
      <div
        ref={containerRef}
        className="h-full w-full"
        aria-label="Google tracking map"
      />

      <div className="solid-tracker-map-controls absolute bottom-6 right-0 z-[10] flex flex-col overflow-hidden rounded-[3px] border border-[#d7dfeb] bg-white shadow-[0_2px_8px_rgba(35,61,102,0.18)]">
        <button
          type="button"
          aria-label="Zoom in"
          title="Zoom in"
          disabled={loadState !== "ready"}
          onClick={() => changeZoom(1)}
          className="grid h-8 w-8 place-items-center border-b border-[#e1e7f0] text-lg font-medium leading-none text-[#52698e] transition hover:bg-[#f2f6fb] disabled:cursor-not-allowed disabled:opacity-50"
        >
          <span aria-hidden="true">+</span>
        </button>

        <button
          type="button"
          aria-label="Zoom out"
          title="Zoom out"
          disabled={loadState !== "ready"}
          onClick={() => changeZoom(-1)}
          className="grid h-8 w-8 place-items-center text-xl font-light leading-none text-[#52698e] transition hover:bg-[#f2f6fb] disabled:cursor-not-allowed disabled:opacity-50"
        >
          <span aria-hidden="true">âˆ’</span>
        </button>
      </div>

      {loadState === "loading" ? (
        <div className="pointer-events-none absolute inset-0 grid place-items-center bg-[#a9d5df] text-sm font-semibold text-white">
          Loading Google Maps...
        </div>
      ) : null}

      {loadState === "error" ? (
        <div className="absolute inset-0 grid place-items-center bg-[#eef3f8] px-6 text-center">
          <div className="max-w-md rounded-md border border-[#f0c8cf] bg-white px-5 py-4 shadow-sm">
            <p className="text-sm font-semibold text-[#9d3042]">
              Google Maps is unavailable
            </p>
            <p className="mt-2 text-xs leading-5 text-[#71819c]">
              {loadError ||
                "Verify the API key, Maps JavaScript API, billing, and website restrictions."}
            </p>
          </div>
        </div>
      ) : null}
    </div>
  );
}