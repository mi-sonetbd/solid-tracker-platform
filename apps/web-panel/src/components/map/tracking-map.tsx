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
  TrackingMapLocationCommand,
  TrackingMapLocationStatus,
  TrackingMapPosition,
  TrackingMapZoomCommand,
} from "@/components/map/tracking-map-types";

type TrackingMapProps = {
  selectedPosition?: TrackingMapPosition | null;
  basemap?: TrackingMapBasemap;
  zoomCommand?: TrackingMapZoomCommand | null;
  streetViewActive?: boolean;
  trafficActive?: boolean;
  myLocationCommand?: TrackingMapLocationCommand | null;
  myLocationActive?: boolean;
  onMyLocationStatusChange?: (
    status: TrackingMapLocationStatus,
  ) => void;
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

function streetViewMarkerRadius(
  map: google.maps.Map,
  position: google.maps.LatLng,
) {
  const zoom = map.getZoom() ?? 13;
  const latitudeRadians =
    (position.lat() * Math.PI) / 180;
  const metersPerPixel =
    (156543.03392 *
      Math.cos(latitudeRadians)) /
    2 ** zoom;

  return Math.max(
    5,
    metersPerPixel * 7,
  );
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


function vehicleMarkerGlyph(
  vehicleType:
    TrackingMapPosition["vehicleType"],
) {
  switch (vehicleType) {
    case "MOTORCYCLE":
      return [
        '<circle cx="18" cy="35" r="5" fill="none" stroke="#ffffff" stroke-width="2.5"/>',
        '<circle cx="38" cy="35" r="5" fill="none" stroke="#ffffff" stroke-width="2.5"/>',
        '<path d="M18 35l7-11h6l7 11M25 24l5 11M22 29h13M31 21h5" fill="none" stroke="#ffffff" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/>',
      ].join("");

    case "CNG":
      return [
        '<path d="M15 31h3l3-10h14l6 10v7h-4v-3H19v3h-4v-7zm8-7-2 7h16l-3-7H23z" fill="#ffffff"/>',
        '<path d="M23 21c1-4 10-4 12 0" fill="none" stroke="#ffffff" stroke-width="2.5" stroke-linecap="round"/>',
        '<circle cx="21" cy="35" r="2.5" fill="#357cf4"/>',
        '<circle cx="35" cy="35" r="2.5" fill="#357cf4"/>',
      ].join("");

    default:
      return [
        '<path d="M14 31l3-8c.7-2 2.1-3 4.2-3h13.6c2.1 0 3.5 1 4.2 3l3 8v8h-4v-3H18v3h-4v-8zm6-7-2 6h20l-2-6H20z" fill="#ffffff"/>',
        '<circle cx="20" cy="34" r="2.5" fill="#357cf4"/>',
        '<circle cx="36" cy="34" r="2.5" fill="#357cf4"/>',
      ].join("");
  }
}

const carStateIconUrl: Record<
  NonNullable<
    TrackingMapPosition["vehicleState"]
  >,
  string
> = {
  moving: "/map-vehicles/car-moving.png",
  idle: "/map-vehicles/car-idle.png",
  stopped: "/map-vehicles/car-stopped.png",
  offline: "/map-vehicles/car-offline.png",
};

function vehicleMarkerIcon(
  vehicleType:
    TrackingMapPosition["vehicleType"],
  vehicleState:
    TrackingMapPosition["vehicleState"],
): google.maps.Icon {
  if (
    vehicleType !== "MOTORCYCLE" &&
    vehicleType !== "CNG"
  ) {
    const state =
      vehicleState ?? "offline";

    return {
      url: carStateIconUrl[state],
      scaledSize: new google.maps.Size(
        36,
        70,
      ),
      anchor: new google.maps.Point(
        18,
        35,
      ),
    };
  }

  const glyph =
    vehicleMarkerGlyph(vehicleType);

  const svg = [
    '<svg xmlns="http://www.w3.org/2000/svg" width="56" height="64" viewBox="0 0 56 64">',
    '<defs><filter id="shadow" x="-30%" y="-30%" width="160%" height="170%"><feDropShadow dx="0" dy="2" stdDeviation="2" flood-color="#203858" flood-opacity=".35"/></filter></defs>',
    '<path filter="url(#shadow)" d="M28 2C13.64 2 2 13.64 2 28c0 18.5 26 34 26 34s26-15.5 26-34C54 13.64 42.36 2 28 2Z" fill="#357cf4" stroke="#ffffff" stroke-width="3"/>',
    '<circle cx="28" cy="28" r="19" fill="#ffffff" fill-opacity=".08"/>',
    glyph,
    '</svg>',
  ].join("");

  return {
    url:
      "data:image/svg+xml;charset=UTF-8," +
      encodeURIComponent(svg),
    scaledSize: new google.maps.Size(
      56,
      64,
    ),
    anchor: new google.maps.Point(
      28,
      61,
    ),
  };
}

export default function TrackingMap({
  selectedPosition = null,
  basemap = "google-hybrid",
  zoomCommand = null,
  streetViewActive = false,
  trafficActive = false,
  myLocationCommand = null,
  myLocationActive = false,
  onMyLocationStatusChange,
}: TrackingMapProps) {
  const containerRef =
    useRef<HTMLDivElement | null>(null);
  const mapRef =
    useRef<google.maps.Map | null>(null);
  const esriReferenceRef =
    useRef<google.maps.ImageMapType | null>(
      null,
    );
  const streetViewServiceRef =
    useRef<google.maps.StreetViewService | null>(
      null,
    );
  const trafficLayerRef =
    useRef<google.maps.TrafficLayer | null>(
      null,
    );
  const myLocationCircleRef =
    useRef<google.maps.Circle | null>(
      null,
    );
  const myLocationInfoWindowRef =
    useRef<google.maps.InfoWindow | null>(
      null,
    );
  const streetViewClickListenerRef =
    useRef<google.maps.MapsEventListener | null>(
      null,
    );
  const streetViewSelectionCircleRef =
    useRef<google.maps.Circle | null>(
      null,
    );
  const streetViewInfoWindowRef =
    useRef<google.maps.InfoWindow | null>(
      null,
    );
  const streetViewRequestIdRef =
    useRef(0);
  const positionMarkerRef =
    useRef<google.maps.Marker | null>(
      null,
    );
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
  const [
    myLocationError,
    setMyLocationError,
  ] = useState("");

  const clearPositionOverlay =
    useCallback(() => {
      positionClickListenerRef.current?.remove();
      positionClickListenerRef.current = null;

      positionMarkerRef.current?.setMap(null);
      positionMarkerRef.current = null;

      infoWindowRef.current?.close();
      infoWindowRef.current = null;
    }, []);

  const clearStreetViewSelection =
    useCallback(() => {
      streetViewRequestIdRef.current += 1;

      streetViewClickListenerRef.current?.remove();
      streetViewClickListenerRef.current = null;

      streetViewSelectionCircleRef.current?.setMap(
        null,
      );
      streetViewSelectionCircleRef.current = null;

      streetViewInfoWindowRef.current?.close();
      streetViewInfoWindowRef.current = null;

      const map = mapRef.current;

      if (map) {
        map.setOptions({
          draggableCursor: null,
        });

        map
          .getStreetView()
          .setVisible(false);
      }
    }, []);

  const clearMyLocationOverlay =
    useCallback(() => {
      myLocationCircleRef.current?.setMap(
        null,
      );
      myLocationCircleRef.current = null;

      myLocationInfoWindowRef.current?.close();
      myLocationInfoWindowRef.current = null;
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

        await Promise.all([
          importLibrary("maps"),
          importLibrary("streetView"),
        ]);

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
        streetViewServiceRef.current =
          new google.maps.StreetViewService();
        trafficLayerRef.current =
          new google.maps.TrafficLayer();

        const panorama =
          map.getStreetView();

        panorama.setOptions({
          addressControl: true,
          clickToGo: true,
          disableDefaultUI: false,
          enableCloseButton: false,
          fullscreenControl: false,
          linksControl: true,
          motionTracking: false,
          motionTrackingControl: false,
          panControl: true,
          zoomControl: true,
        });

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
      clearMyLocationOverlay();

      if (mapRef.current) {
        google.maps.event
          .clearInstanceListeners(
            mapRef.current,
          );
      }

      if (mapRef.current) {
        mapRef.current
          .getStreetView()
          .setVisible(false);
      }

      mapRef.current = null;
      esriReferenceRef.current = null;
      trafficLayerRef.current?.setMap(null);
      trafficLayerRef.current = null;
      streetViewServiceRef.current = null;
    };
  }, [
    apiKey,
    clearMyLocationOverlay,
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

    if (!myLocationActive) {
      clearMyLocationOverlay();
      return;
    }

    if (!myLocationCommand) {
      return;
    }

    queueMicrotask(() => {
      setMyLocationError("");
    });

    onMyLocationStatusChange?.(
      "locating",
    );

    if (!navigator.geolocation) {
      queueMicrotask(() => {
        setMyLocationError(
          "Location access is not supported by this browser.",
        );
        onMyLocationStatusChange?.(
          "error",
        );
      });

      return;
    }

    let cancelled = false;

    navigator.geolocation.getCurrentPosition(
      (position) => {
        if (cancelled) {
          return;
        }

        const location:
          google.maps.LatLngLiteral = {
            lat: position.coords.latitude,
            lng: position.coords.longitude,
          };

        clearMyLocationOverlay();

        map.setCenter(location);
        map.setZoom(
          Math.max(
            map.getZoom() ?? 16,
            16,
          ),
        );

        const circle =
          new google.maps.Circle({
            map,
            center: location,
            radius: Math.max(
              8,
              position.coords.accuracy,
            ),
            strokeColor: "#ffffff",
            strokeOpacity: 1,
            strokeWeight: 3,
            fillColor: "#357cf4",
            fillOpacity: 0.88,
            clickable: true,
            zIndex: 1300,
          });

        const content =
          document.createElement("div");

        content.className =
          "px-1 py-0.5 text-xs font-semibold text-[#344b72]";
        content.textContent =
          "My location";

        const infoWindow =
          new google.maps.InfoWindow({
            content,
            position: location,
            disableAutoPan: false,
          });

        const listener =
          circle.addListener(
            "click",
            () => {
              infoWindow.open({
                map,
                shouldFocus: false,
              });
            },
          );

        google.maps.event.addListenerOnce(
          circle,
          "map_changed",
          () => {
            if (!circle.getMap()) {
              listener.remove();
            }
          },
        );

        myLocationCircleRef.current =
          circle;
        myLocationInfoWindowRef.current =
          infoWindow;

        onMyLocationStatusChange?.(
          "ready",
        );
      },
      (error) => {
        if (cancelled) {
          return;
        }

        const message =
          error.code ===
          error.PERMISSION_DENIED
            ? "Location permission was denied."
            : error.code ===
                error.POSITION_UNAVAILABLE
              ? "Current location is unavailable."
              : "Location request timed out.";

        setMyLocationError(message);
        onMyLocationStatusChange?.(
          "error",
        );
      },
      {
        enableHighAccuracy: true,
        maximumAge: 15000,
        timeout: 10000,
      },
    );

    return () => {
      cancelled = true;
    };
  }, [
    clearMyLocationOverlay,
    loadState,
    myLocationActive,
    myLocationCommand,
    onMyLocationStatusChange,
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
    const trafficLayer =
      trafficLayerRef.current;

    if (
      !map ||
      !trafficLayer ||
      loadState !== "ready"
    ) {
      return;
    }

    if (!trafficActive) {
      trafficLayer.setMap(null);
      return;
    }

    trafficLayer.setMap(null);
    trafficLayer.setMap(map);
  }, [
    basemap,
    loadState,
    trafficActive,
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
    const service =
      streetViewServiceRef.current;

    if (
      !map ||
      !service ||
      loadState !== "ready"
    ) {
      return;
    }

    clearStreetViewSelection();

    if (!streetViewActive) {
      return;
    }

    const streetViewService = service;
    const panorama =
      map.getStreetView();

    map.setOptions({
      draggableCursor: "crosshair",
    });

    const clickListener = map.addListener(
      "click",
      (
        event: google.maps.MapMouseEvent,
      ) => {
        const selectedPoint =
          event.latLng;

        if (!selectedPoint) {
          return;
        }

        const requestId =
          streetViewRequestIdRef.current + 1;

        streetViewRequestIdRef.current =
          requestId;

        streetViewSelectionCircleRef.current?.setMap(
          null,
        );
        streetViewInfoWindowRef.current?.close();

        panorama.setVisible(false);

        const selectionCircle =
          new google.maps.Circle({
            map,
            center: selectedPoint,
            radius: streetViewMarkerRadius(
              map,
              selectedPoint,
            ),
            strokeColor: "#ffffff",
            strokeOpacity: 1,
            strokeWeight: 3,
            fillColor: "#357cf4",
            fillOpacity: 1,
            clickable: false,
            zIndex: 1200,
          });

        const statusWindow =
          new google.maps.InfoWindow({
            content:
              "Searching Street View...",
            position: selectedPoint,
            disableAutoPan: true,
          });

        statusWindow.open({
          map,
          shouldFocus: false,
        });

        streetViewSelectionCircleRef.current =
          selectionCircle;
        streetViewInfoWindowRef.current =
          statusWindow;

        void streetViewService
          .getPanorama({
            location: selectedPoint,
            preference:
              google.maps
                .StreetViewPreference
                .NEAREST,
            radius: 1000,
            sources: [
              google.maps
                .StreetViewSource
                .OUTDOOR,
            ],
          })
          .then((response) => {
            if (
              streetViewRequestIdRef.current !==
              requestId
            ) {
              return;
            }

            const location =
              response.data.location;

            if (!location?.pano) {
              statusWindow.setContent(
                "No Street View found near this point.",
              );
              return;
            }

            const panoramaPosition =
              location.latLng ??
              selectedPoint;

            selectionCircle.setCenter(
              panoramaPosition,
            );
            selectionCircle.setRadius(
              streetViewMarkerRadius(
                map,
                panoramaPosition,
              ),
            );

            statusWindow.close();

            map.setOptions({
              draggableCursor: null,
            });

            panorama.setPano(
              location.pano,
            );
            panorama.setPov({
              heading: 0,
              pitch: 0,
            });
            panorama.setVisible(true);
          })
          .catch(() => {
            if (
              streetViewRequestIdRef.current !==
              requestId
            ) {
              return;
            }

            statusWindow.setContent(
              "No Street View found near this point.",
            );
          });
      },
    );

    streetViewClickListenerRef.current =
      clickListener;

    return clearStreetViewSelection;
  }, [
    clearStreetViewSelection,
    loadState,
    streetViewActive,
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

    const marker =
      new google.maps.Marker({
        map,
        position,
        icon: vehicleMarkerIcon(
          selectedPosition.vehicleType,
          selectedPosition.vehicleState,
        ),
        title: selectedPosition.label,
        clickable: true,
        optimized: false,
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
        disableAutoPan: false,
      });

    const clickListener =
      marker.addListener(
        "click",
        () => {
          infoWindow.open({
            map,
            anchor: marker,
            shouldFocus: false,
          });
        },
      );

    positionMarkerRef.current = marker;
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

      {myLocationError ? (
        <div
          role="status"
          className="pointer-events-none absolute left-1/2 top-3 z-[20] -translate-x-1/2 rounded border border-[#e1b9c1] bg-white px-3 py-2 text-xs font-medium text-[#9d3042] shadow-md"
        >
          {myLocationError}
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