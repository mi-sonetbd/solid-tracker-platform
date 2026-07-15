"use client";

import { useEffect, useState } from "react";
import {
  normalizeCustomerVehicle,
  type CustomerAssetListResponse,
  type CustomerVehicleAsset,
} from "@/lib/customer/customer-asset-types";
import type { ManagementApiError } from "@/lib/management/dealer-types";

export function useCustomerAssets(
  canViewVehicles: boolean,
) {
  const [vehicles, setVehicles] = useState<
    CustomerVehicleAsset[]
  >([]);
  const [loading, setLoading] =
    useState(canViewVehicles);
  const [error, setError] = useState("");
  const [refreshVersion, setRefreshVersion] =
    useState(0);

  useEffect(() => {
    if (!canViewVehicles) {
      return;
    }

    const controller = new AbortController();

    fetch("/api/customer/assets?page=1&pageSize=100", {
      cache: "no-store",
      signal: controller.signal,
    })
      .then(async (response) => {
        const payload = (await response.json()) as
          | CustomerAssetListResponse
          | ManagementApiError;

        if (!response.ok) {
          throw new Error(
            "message" in payload
              ? payload.message
              : "Customer assets could not be loaded.",
          );
        }

        return payload as CustomerAssetListResponse;
      })
      .then((payload) => {
        setVehicles(
          payload.items.map(normalizeCustomerVehicle),
        );
        setError("");
      })
      .catch((requestError: unknown) => {
        if (
          requestError instanceof DOMException &&
          requestError.name === "AbortError"
        ) {
          return;
        }

        setVehicles([]);
        setError(
          requestError instanceof Error
            ? requestError.message
            : "Customer assets could not be loaded.",
        );
      })
      .finally(() => {
        if (!controller.signal.aborted) {
          setLoading(false);
        }
      });

    return () => controller.abort();
  }, [canViewVehicles, refreshVersion]);

  return {
    vehicles: canViewVehicles ? vehicles : [],
    loading: canViewVehicles ? loading : false,
    error: canViewVehicles
      ? error
      : "This Customer login does not have vehicle.view permission.",
    refresh() {
      setLoading(true);
      setRefreshVersion((current) => current + 1);
    },
  };
}