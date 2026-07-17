"use client";

import {
  CarFront,
  CheckCircle2,
  CirclePlus,
  Cpu,
  LoaderCircle,
  RefreshCw,
  Search,
  X,
} from "lucide-react";
import {
  useEffect,
  useState,
  type FormEvent,
} from "react";
import { AddCustomerVehicleModal } from "@/components/management/add-customer-vehicle-modal";
import { InstallCustomerDeviceModal } from "@/components/management/install-customer-device-modal";
import type {
  DeviceInstallationResult,
  VehicleListResponse,
  VehicleSummary,
} from "@/lib/management/asset-types";
import type { CustomerSummary } from "@/lib/management/customer-types";
import type { ManagementApiError } from "@/lib/management/dealer-types";

type CustomerAssetsModalProps = {
  customer: CustomerSummary;
  canCreateVehicles: boolean;
  canViewDevices: boolean;
  canInstallDevices: boolean;
  onClose: () => void;
  onVehicleCountChange: (customerId: string, count: number) => void;
};

function customerName(customer: CustomerSummary) {
  return (
    customer.individualProfile?.fullName ??
    customer.organizationProfile?.displayName ??
    customer.customerCode
  );
}

function vehicleName(vehicle: VehicleSummary) {
  const model = [vehicle.manufacturer, vehicle.modelName]
    .filter(Boolean)
    .join(" ");

  return model || vehicle.vehicleType.replaceAll("_", " ");
}

export function CustomerAssetsModal({
  customer,
  canCreateVehicles,
  canViewDevices,
  canInstallDevices,
  onClose,
  onVehicleCountChange,
}: CustomerAssetsModalProps) {
  const [vehicles, setVehicles] = useState<VehicleSummary[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [success, setSuccess] = useState("");
  const [searchInput, setSearchInput] = useState("");
  const [activeSearch, setActiveSearch] = useState("");
  const [refreshVersion, setRefreshVersion] = useState(0);
  const [addVehicleOpen, setAddVehicleOpen] = useState(false);
  const [installVehicle, setInstallVehicle] =
    useState<VehicleSummary | null>(null);

  useEffect(() => {
    const controller = new AbortController();
    const parameters = new URLSearchParams({
      page: "1",
      pageSize: "100",
      customerId: customer.id,
    });

    if (activeSearch) parameters.set("search", activeSearch);

    fetch(`/api/management/vehicles?${parameters.toString()}`, {
      cache: "no-store",
      signal: controller.signal,
    })
      .then(async (response) => {
        const payload = (await response.json()) as
          | VehicleListResponse
          | ManagementApiError;

        if (!response.ok) {
          throw new Error(
            "message" in payload
              ? payload.message
              : "Customer vehicle loading failed.",
          );
        }

        return payload as VehicleListResponse;
      })
      .then((payload) => {
        setVehicles(payload.items);
        onVehicleCountChange(customer.id, payload.total);
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
            : "Customer vehicle loading failed.",
        );
      })
      .finally(() => {
        if (!controller.signal.aborted) setLoading(false);
      });

    return () => controller.abort();
  }, [
    activeSearch,
    customer.id,
    onVehicleCountChange,
    refreshVersion,
  ]);

  function search(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setLoading(true);
    setActiveSearch(searchInput.trim());
  }

  function vehicleCreated(vehicle: VehicleSummary) {
    setAddVehicleOpen(false);
    setSuccess(
      `Vehicle ${vehicle.registrationNumber || vehicle.vehicleCode} was registered.`,
    );
    setLoading(true);
    setRefreshVersion((value) => value + 1);
  }

  function trackerInstalled(result: DeviceInstallationResult) {
    setInstallVehicle(null);
    setSuccess(
      `Primary tracker installation ${result.installationCode} was completed.`,
    );
    setLoading(true);
    setRefreshVersion((value) => value + 1);
  }

  return (
    <>
      <div
        className="fixed inset-0 z-[2500] grid place-items-center bg-[#17345f]/48 p-5"
        role="presentation"
        onMouseDown={(event) => {
          if (event.target === event.currentTarget) onClose();
        }}
      >
        <section
          role="dialog"
          aria-modal="true"
          aria-labelledby="customer-assets-title"
          className="flex max-h-[94vh] w-full max-w-[1100px] flex-col overflow-hidden rounded-[8px] bg-white shadow-[0_28px_80px_rgba(18,44,86,0.28)]"
        >
          <header className="flex items-start justify-between border-b border-[#e2e8f1] px-6 py-5">
            <div>
              <div className="flex items-center gap-2 text-[#357cf4]">
                <CarFront className="h-5 w-5" />
                <span className="text-[11px] font-semibold uppercase tracking-[0.16em]">
                  Customer Assets
                </span>
              </div>
              <h2
                id="customer-assets-title"
                className="mt-2 text-[18px] font-semibold text-[#344b72]"
              >
                {customerName(customer)}
              </h2>
              <p className="mt-1 text-[11px] text-[#71819c]">
                {customer.customerCode} Â·{" "}
                {customer.managingDealer
                  ? `Managed by ${customer.managingDealer.name}`
                  : "Platform / Direct"}
              </p>
            </div>

            <button
              type="button"
              onClick={onClose}
              className="grid h-9 w-9 place-items-center rounded-full text-[#71819c] hover:bg-[#f2f6fb]"
            >
              <X className="h-5 w-5" />
            </button>
          </header>

          <div className="flex flex-wrap items-center gap-3 border-b border-[#e2e8f1] px-6 py-4">
            <form onSubmit={search} className="flex min-w-[300px] flex-1">
              <div className="relative min-w-0 flex-1">
                <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-[#8b9ab4]" />
                <input
                  value={searchInput}
                  onChange={(event) => setSearchInput(event.target.value)}
                  placeholder="Search vehicle code, registration, chassis, or engine"
                  className="h-10 w-full rounded-l-[4px] border border-[#cfd8e7] pl-10 pr-3 text-[11px] outline-none focus:border-[#357cf4]"
                />
              </div>
              <button
                type="submit"
                className="h-10 rounded-r-[4px] bg-[#52698e] px-4 text-[11px] font-semibold text-white"
              >
                Search
              </button>
            </form>

            <button
              type="button"
              onClick={() => {
                setLoading(true);
                setRefreshVersion((value) => value + 1);
              }}
              disabled={loading}
              className="flex h-10 items-center gap-2 rounded-[4px] border border-[#cfd8e7] px-4 text-[11px] font-semibold text-[#52698e]"
            >
              <RefreshCw
                className={["h-4 w-4", loading ? "animate-spin" : ""].join(
                  " ",
                )}
              />
              Refresh
            </button>

            <button
              type="button"
              onClick={() => setAddVehicleOpen(true)}
              disabled={!canCreateVehicles}
              className="flex h-10 items-center gap-2 rounded-[4px] bg-[#357cf4] px-4 text-[11px] font-semibold text-white disabled:bg-[#b8c7dc]"
            >
              <CirclePlus className="h-4 w-4" />
              Add Vehicle
            </button>
          </div>

          {success ? (
            <div className="mx-6 mt-4 flex items-center gap-2 rounded-[4px] bg-emerald-50 px-4 py-3 text-[11px] font-medium text-emerald-700">
              <CheckCircle2 className="h-4 w-4" />
              {success}
            </div>
          ) : null}

          {error ? (
            <div className="mx-6 mt-4 rounded-[4px] bg-red-50 px-4 py-3 text-[11px] font-medium text-red-700">
              {error}
            </div>
          ) : null}

          <div className="st-scrollbar min-h-[300px] flex-1 overflow-auto px-6 py-5">
            {loading ? (
              <div className="grid min-h-[260px] place-items-center text-[#71819c]">
                <div className="text-center">
                  <LoaderCircle className="mx-auto h-6 w-6 animate-spin" />
                  <p className="mt-3 text-[11px]">
                    Loading scoped Customer vehicles...
                  </p>
                </div>
              </div>
            ) : vehicles.length === 0 ? (
              <div className="grid min-h-[260px] place-items-center rounded-[6px] border border-dashed border-[#cfd8e7] bg-[#fafcff] text-center">
                <div>
                  <CarFront className="mx-auto h-8 w-8 text-[#9aacbf]" />
                  <p className="mt-3 text-[12px] font-semibold text-[#52698e]">
                    No vehicle is registered for this Customer.
                  </p>
                  <p className="mt-1 text-[10px] text-[#8b9ab4]">
                    Register the first vehicle before installing a tracker.
                  </p>
                </div>
              </div>
            ) : (
              <div className="overflow-hidden rounded-[6px] border border-[#dfe6ef]">
                <table className="w-full min-w-[940px] text-left text-[10px]">
                  <thead className="bg-[#f4f7fb] text-[#52698e]">
                    <tr>
                      {[
                        "Vehicle",
                        "Code",
                        "Type",
                        "Registration",
                        "Identity",
                        "Primary Tracker",
                        "Status",
                        "Action",
                      ].map((heading) => (
                        <th
                          key={heading}
                          className="px-4 py-3 font-semibold"
                        >
                          {heading}
                        </th>
                      ))}
                    </tr>
                  </thead>

                  <tbody>
                    {vehicles.map((vehicle) => {
                      const assignment = vehicle.deviceAssignments[0] ?? null;
                      const device = assignment?.device ?? null;

                      return (
                        <tr
                          key={vehicle.id}
                          className="border-t border-[#e2e8f1] text-[#52698e]"
                        >
                          <td className="px-4 py-4">
                            <p className="font-semibold text-[#405779]">
                              {vehicleName(vehicle)}
                            </p>
                            <p className="mt-1 text-[9px] text-[#8b9ab4]">
                              {vehicle.manufacturingYear || "-"} Â·{" "}
                              {vehicle.color || "-"}
                            </p>
                          </td>

                          <td className="px-4 py-4 font-medium text-[#357cf4]">
                            {vehicle.vehicleCode}
                          </td>

                          <td className="px-4 py-4">
                            {vehicle.vehicleType.replaceAll("_", " ")}
                          </td>

                          <td className="px-4 py-4">
                            {vehicle.registrationNumber || "-"}
                          </td>

                          <td className="px-4 py-4">
                            <p>Chassis: {vehicle.chassisNumber || "-"}</p>
                            <p className="mt-1">
                              Engine: {vehicle.engineNumber || "-"}
                            </p>
                          </td>

                          <td className="px-4 py-4">
                            {device ? (
                              <>
                                <p className="font-semibold text-[#405779]">
                                  {device.deviceCode}
                                </p>
                                <p className="mt-1 text-[9px] text-[#8b9ab4]">
                                  IMEI {device.imei || "-"}
                                </p>
                              </>
                            ) : (
                              <span className="rounded-full bg-amber-50 px-2 py-1 text-[9px] font-semibold text-amber-700">
                                Not installed
                              </span>
                            )}
                          </td>

                          <td className="px-4 py-4">
                            <span className="rounded-full bg-emerald-50 px-2 py-1 text-[9px] font-semibold text-emerald-700">
                              {vehicle.status}
                            </span>
                          </td>

                          <td className="px-4 py-4">
                            <button
                              type="button"
                              onClick={() => setInstallVehicle(vehicle)}
                              disabled={
                                Boolean(device) ||
                                !canViewDevices ||
                                !canInstallDevices
                              }
                              className="flex h-8 items-center gap-2 rounded-[3px] bg-[#357cf4] px-3 text-[10px] font-semibold text-white disabled:bg-[#b8c7dc]"
                            >
                              <Cpu className="h-3.5 w-3.5" />
                              {device ? "Installed" : "Install Tracker"}
                            </button>
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            )}
          </div>
        </section>
      </div>

      {addVehicleOpen ? (
        <AddCustomerVehicleModal
          customer={customer}
          onClose={() => setAddVehicleOpen(false)}
          onCreated={vehicleCreated}
        />
      ) : null}

      {installVehicle ? (
        <InstallCustomerDeviceModal
          customer={customer}
          vehicle={installVehicle}
          canViewDevices={canViewDevices}
          onClose={() => setInstallVehicle(null)}
          onInstalled={trackerInstalled}
        />
      ) : null}
    </>
  );
}