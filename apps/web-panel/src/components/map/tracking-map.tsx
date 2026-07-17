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
  TrackingMapZoomCommand,
} from "@/components/map/tracking-map-types";

type TrackingMapProps = {
  selectedPosition?: TrackingMapPosition | null;
  basemap?: TrackingMapBasemap;
  zoomCommand?: TrackingMapZoomCommand | null;
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
  lat: 23.8103,
  lng: 90.4125,
};

const esriImageryMapTypeId =
  "solid-tracker-esri-imagery";

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

function normalizedTileUrl(
  serviceName: string,
  coordinate: google.maps.Point,
  zoom: number,
) {
  const scale = 1 << zoom;

  if (
    coordinate.y < 0 ||
    coordinate.y >= scale
  ) {
    return "";
  }

  const x =
    ((coordinate.x % scale) + scale) %
    scale;

  return [
    "https://server.arcgisonline.com",
    "ArcGIS",
    "rest",
    "services",
    serviceName,
    "MapServer",
    "tile",
    String(zoom),
    String(coordinate.y),
    String(x),
  ].join("/");
}

function createEsriImageryType() {
  return new google.maps.ImageMapType({
    alt: "Esri World Imagery",
    name: "OpenStreet Satellite",
    tileSize: new google.maps.Size(
      256,
      256,
    ),
    minZoom: 0,
    maxZoom: 19,
    getTileUrl: (coordinate, zoom) =>
      normalizedTileUrl(
        "World_Imagery",
        coordinate,
        zoom,
      ),
  });
}

function createEsriReferenceType() {
  return new google.maps.ImageMapType({
    alt: "Esri boundaries and places",
    name: "OpenStreet Hybrid labels",
    tileSize: new google.maps.Size(
      256,
      256,
    ),
    minZoom: 0,
    maxZoom: 19,
    getTileUrl: (coordinate, zoom) =>
      normalizedTileUrl(
        "Reference/World_Boundaries_and_Places",
        coordinate,
        zoom,
      ),
  });
}

function applyBasemap(
  map: google.maps.Map,
  basemap: TrackingMapBasemap,
  esriReference:
    google.maps.ImageMapType | null,
) {
  map.overlayMapTypes.clear();

  switch (basemap) {
    case "google-roadmap":
      map.setMapTypeId(
        google.maps.MapTypeId.ROADMAP,
      );
      return;

    case "google-satellite":
      map.setMapTypeId(
        google.maps.MapTypeId.SATELLITE,
      );
      return;

    case "openstreet-hybrid":
      map.setMapTypeId(
        esriImageryMapTypeId,
      );

      if (esriReference) {
        map.overlayMapTypes.push(
          esriReference,
        );
      }
      return;

    case "openstreet-satellite":
      map.setMapTypeId(
        esriImageryMapTypeId,
      );
      return;

    case "google-hybrid":
    default:
      map.setMapTypeId(
        google.maps.MapTypeId.HYBRID,
      );
  }
}

export default function TrackingMap({
  selectedPosition = null,
  basemap = "google-hybrid",
  zoomCommand = null,
}: TrackingMapProps) {
  const containerRef =
    useRef<HTMLDivElement | null>(null);
  const mapRef =
    useRef<google.maps.Map | null>(null);
  const esriReferenceRef =
    useRef<google.maps.ImageMapType | null>(
      null,
    );
  const positionCircleRef =
    useRef<google.maps.Circle | null>(null);
  const positionClickListenerRef =
    useRef<google.maps.MapsEventListener | null>(
      null,
    );
  const infoWindowRef =
    useRef<google.maps.InfoWindow | null>(
      null,
    );

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

    if (!container || !apiKey) {
      return;
    }

    const mapContainer = container;
    const googleMapsApiKey = apiKey;

    let disposed = false;
    let resizeFrame: number | null = null;
    let resizeObserver:
      ResizeObserver | null = null;

    async function initializeMap() {
      try {
        configureGoogleMaps(
          googleMapsApiKey,
        );

        await importLibrary("maps");

        if (
          disposed ||
          !mapContainer.isConnected
        ) {
          return;
        }

        const map = new google.maps.Map(
          mapContainer,
          {
            center: defaultCenter,
            zoom: 13,
            minZoom: 2,
            mapTypeId:
              google.maps.MapTypeId.HYBRID,
            disableDefaultUI: true,
            keyboardShortcuts: false,
            clickableIcons: false,
            gestureHandling: "greedy",
            backgroundColor: "#a9d5df",
          },
        );

        const esriImagery =
          createEsriImageryType();
        const esriReference =
          createEsriReferenceType();

        map.mapTypes.set(
          esriImageryMapTypeId,
          esriImagery,
        );

        esriReferenceRef.current =
          esriReference;
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
              cancelAnimationFrame(
                resizeFrame,
              );
            }

            const center = map.getCenter();

            resizeFrame =
              requestAnimationFrame(() => {
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
              });
          },
        );

        resizeObserver.observe(
          mapContainer,
        );

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
        cancelAnimationFrame(
          resizeFrame,
        );
      }

      resizeObserver?.disconnect();
      clearPositionOverlay();

      if (mapRef.current) {
        google.maps.event
          .clearInstanceListeners(
            mapRef.current,
          );
      }

      mapRef.current = null;
      esriReferenceRef.current = null;
    };
  }, [
    apiKey,
    clearPositionOverlay,
  ]);

  useEffect(() => {
    const map = mapRef.current;

    if (
      !map ||
      loadState !== "ready"
    ) {
      return;
    }

    applyBasemap(
      map,
      basemap,
      esriReferenceRef.current,
    );
  }, [
    basemap,
    loadState,
  ]);

  useEffect(() => {
    const map = mapRef.current;

    if (
      !map ||
      loadState !== "ready" ||
      !zoomCommand
    ) {
      return;
    }

    const currentZoom =
      map.getZoom() ?? 13;

    map.setZoom(
      Math.max(
        2,
        Math.min(
          21,
          currentZoom +
            zoomCommand.delta,
        ),
      ),
    );
  }, [
    loadState,
    zoomCommand,
  ]);

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

    const circle =
      new google.maps.Circle({
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

    const clickListener =
      circle.addListener(
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

  const usesEsri =
    basemap === "openstreet-hybrid" ||
    basemap === "openstreet-satellite";

  return (
    <div className="relative h-full w-full bg-[#a9d5df]">
      <div
        ref={containerRef}
        className="h-full w-full"
        aria-label="Tracking map"
      />

      {usesEsri &&
      loadState === "ready" ? (
        <div className="pointer-events-none absolute bottom-0 left-0 z-[5] bg-white/90 px-1.5 py-0.5 text-[9px] text-[#4d5e79]">
          Tiles Â© Esri
        </div>
      ) : null}

      {loadState === "loading" ? (
        <div className="pointer-events-none absolute inset-0 grid place-items-center bg-[#a9d5df] text-sm font-semibold text-white">
          Loading map...
        </div>
      ) : null}

      {loadState === "error" ? (
        <div className="absolute inset-0 grid place-items-center bg-[#eef3f8] px-6 text-center">
          <div className="max-w-md rounded-md border border-[#f0c8cf] bg-white px-5 py-4 shadow-sm">
            <p className="text-sm font-semibold text-[#9d3042]">
              Map is unavailable
            </p>
            <p className="mt-2 text-xs leading-5 text-[#71819c]">
              {loadError ||
                "Verify the map provider configuration and network access."}
            </p>
          </div>
        </div>
      ) : null}
    </div>
  );
}