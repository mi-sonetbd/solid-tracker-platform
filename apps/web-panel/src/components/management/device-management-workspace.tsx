"use client";

import {
  Boxes,
  Building2,
  CheckCircle2,
  CirclePlus,
  Cpu,
  LoaderCircle,
  PackageCheck,
  RefreshCw,
  Search,
  ShieldCheck,
} from "lucide-react";
import {
  useEffect,
  useMemo,
  useState,
  type FormEvent,
} from "react";
import { AccountTree } from "@/components/management/account-tree";
import { AddDeviceModelModal } from "@/components/management/add-device-model-modal";
import { AllocateDeviceModal } from "@/components/management/allocate-device-modal";
import { DeviceStockIntakeModal } from "@/components/management/device-stock-intake-modal";
import type {
  DealerDeviceAllocationResult,
  DeviceListResponse,
  DeviceModelListResponse,
  DeviceModelSummary,
  DeviceSummary,
} from "@/lib/management/asset-types";
import type { ManagementApiError } from "@/lib/management/dealer-types";

type DeviceManagementWorkspaceProps = {
  workspace: string;
  canViewDevices: boolean;
  canRegisterDevices: boolean;
  canAllocateDevices: boolean;
};

const lifecycleOptions = [
  "",
  "RECEIVED",
  "IN_STOCK",
  "RESERVED",
  "ALLOCATED",
  "INSTALLED",
  "UNDER_REPAIR",
  "LOST",
  "DAMAGED",
  "RETIRED",
];

function formatDate(value?: string | null) {
  if (!value) return "-";

  const date = new Date(value);

  if (Number.isNaN(date.getTime())) return "-";

  return new Intl.DateTimeFormat("en-GB", {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(date);
}

function custodyLabel(device: DeviceSummary) {
  const allocation = device.dealerAllocations?.[0];

  if (allocation) {
    return allocation.dealerOrganization.name;
  }

  if (device.lifecycleStatus === "INSTALLED") {
    return "Customer vehicle";
  }

  return "Solid Tracker Platform";
}

function normalizeDevice(device: DeviceSummary): DeviceSummary {
  return {
    ...device,
    dealerAllocations: device.dealerAllocations ?? [],
    vehicleAssignments: device.vehicleAssignments ?? [],
    ownershipHistory: device.ownershipHistory ?? [],
    custodyHistory: device.custodyHistory ?? [],
  };
}

function statusClass(status: string) {
  if (status === "IN_STOCK" || status === "RECEIVED") {
    return "bg-emerald-50 text-emerald-700";
  }

  if (status === "ALLOCATED") {
    return "bg-indigo-50 text-indigo-700";
  }

  if (status === "INSTALLED") {
    return "bg-sky-50 text-sky-700";
  }

  if (
    status === "DAMAGED" ||
    status === "LOST" ||
    status === "RETIRED"
  ) {
    return "bg-red-50 text-red-700";
  }

  return "bg-amber-50 text-amber-700";
}

export function DeviceManagementWorkspace({
  workspace,
  canViewDevices,
  canRegisterDevices,
  canAllocateDevices,
}: DeviceManagementWorkspaceProps) {
  const [devices, setDevices] = useState<DeviceSummary[]>([]);
  const [models, setModels] = useState<DeviceModelSummary[]>([]);
  const [loading, setLoading] = useState(canViewDevices);
  const [error, setError] = useState("");
  const [success, setSuccess] = useState("");
  const [searchInput, setSearchInput] = useState("");
  const [activeSearch, setActiveSearch] = useState("");
  const [lifecycleStatus, setLifecycleStatus] = useState("");
  const [deviceModelId, setDeviceModelId] = useState("");
  const [refreshVersion, setRefreshVersion] = useState(0);
  const [modelRefreshVersion, setModelRefreshVersion] =
    useState(0);
  const [modelModalOpen, setModelModalOpen] = useState(false);
  const [stockModalOpen, setStockModalOpen] = useState(false);
  const [allocationDevice, setAllocationDevice] =
    useState<DeviceSummary | null>(null);

  useEffect(() => {
    if (!canViewDevices) return;

    const controller = new AbortController();
    const parameters = new URLSearchParams({
      page: "1",
      pageSize: "100",
    });

    if (activeSearch) parameters.set("search", activeSearch);
    if (lifecycleStatus) {
      parameters.set("lifecycleStatus", lifecycleStatus);
    }
    if (deviceModelId) {
      parameters.set("deviceModelId", deviceModelId);
    }

    fetch(`/api/management/devices?${parameters.toString()}`, {
      cache: "no-store",
      signal: controller.signal,
    })
      .then(async (response) => {
        const payload = (await response.json()) as
          | DeviceListResponse
          | ManagementApiError;

        if (!response.ok) {
          throw new Error(
            "message" in payload
              ? payload.message
              : "Device inventory loading failed.",
          );
        }

        return payload as DeviceListResponse;
      })
      .then((payload) => {
        setDevices(payload.items.map(normalizeDevice));
        setError("");
      })
      .catch((requestError: unknown) => {
        if (
          requestError instanceof DOMException &&
          requestError.name === "AbortError"
        ) {
          return;
        }

        setDevices([]);
        setError(
          requestError instanceof Error
            ? requestError.message
            : "Device inventory loading failed.",
        );
      })
      .finally(() => {
        if (!controller.signal.aborted) {
          setLoading(false);
        }
      });

    return () => controller.abort();
  }, [
    activeSearch,
    canViewDevices,
    deviceModelId,
    lifecycleStatus,
    refreshVersion,
  ]);

  useEffect(() => {
    if (!canViewDevices) return;

    const controller = new AbortController();

    fetch("/api/management/device-models?page=1&pageSize=100", {
      cache: "no-store",
      signal: controller.signal,
    })
      .then(async (response) => {
        const payload = (await response.json()) as
          | DeviceModelListResponse
          | ManagementApiError;

        if (!response.ok) {
          throw new Error(
            "message" in payload
              ? payload.message
              : "Device Model loading failed.",
          );
        }

        return payload as DeviceModelListResponse;
      })
      .then((payload) => {
        setModels(payload.items);
      })
      .catch((requestError: unknown) => {
        if (
          requestError instanceof DOMException &&
          requestError.name === "AbortError"
        ) {
          return;
        }

        setError(
          requestError instanceof Error
            ? requestError.message
            : "Device Model loading failed.",
        );
      });

    return () => controller.abort();
  }, [canViewDevices, modelRefreshVersion]);

  const statistics = useMemo(
    () => ({
      total: devices.length,
      platformStock: devices.filter(
        (device) =>
          ["RECEIVED", "IN_STOCK"].includes(
            device.lifecycleStatus,
          ) && (device.dealerAllocations?.length ?? 0) === 0,
      ).length,
      dealerStock: devices.filter(
        (device) => device.lifecycleStatus === "ALLOCATED",
      ).length,
      installed: devices.filter(
        (device) => device.lifecycleStatus === "INSTALLED",
      ).length,
    }),
    [devices],
  );

  function search(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setLoading(true);
    setActiveSearch(searchInput.trim());
  }

  function refresh() {
    setLoading(true);
    setRefreshVersion((value) => value + 1);
    setModelRefreshVersion((value) => value + 1);
  }

  function modelCreated(model: DeviceModelSummary) {
    setModelModalOpen(false);
    setModels((current) => [
      model,
      ...current.filter((item) => item.id !== model.id),
    ]);
    setSuccess(
      `Device Model ${model.manufacturer} ${model.modelName} was created.`,
    );
    setModelRefreshVersion((value) => value + 1);
  }

  function deviceCreated(device: DeviceSummary) {
    setStockModalOpen(false);
    const normalizedDevice = normalizeDevice(device);

    setDevices((current) => [
      normalizedDevice,
      ...current.filter((item) => item.id !== device.id),
    ]);
    setSuccess(
      `${device.deviceCode} entered Platform stock with lifecycle IN_STOCK.`,
    );
    setRefreshVersion((value) => value + 1);
  }

  function deviceAllocated(
    allocation: DealerDeviceAllocationResult,
  ) {
    setAllocationDevice(null);
    setSuccess(
      `${allocation.device.deviceCode} was allocated to ${allocation.dealerOrganization.name}.`,
    );
    setLoading(true);
    setRefreshVersion((value) => value + 1);
  }

  return (
    <>
      <div className="flex h-[calc(100vh-var(--st-topbar-height))] min-w-[1180px] overflow-hidden p-2">
        <AccountTree />

        <section className="st-scrollbar min-w-0 flex-1 overflow-auto rounded-r-[6px] bg-[#eef2f7] p-4">
          <div className="rounded-[8px] bg-white p-5 shadow-sm">
            <header className="flex flex-wrap items-start justify-between gap-4 border-b border-[#e2e8f1] pb-4">
              <div>
                <div className="flex items-center gap-2 text-[#357cf4]">
                  <Boxes className="h-5 w-5" />
                  <span className="text-[10px] font-semibold uppercase tracking-[0.18em]">
                    Asset Inventory
                  </span>
                </div>
                <h1 className="mt-2 text-[19px] font-semibold text-[#344b72]">
                  Device Management
                </h1>
                <p className="mt-1 text-[11px] text-[#71819c]">
                  Device Models, Platform stock intake, Dealer
                  allocation, and installed tracker visibility.
                </p>
              </div>

              <div className="flex items-center gap-2">
                <span className="mr-2 rounded-full bg-[#eaf2ff] px-3 py-1 text-[10px] font-semibold text-[#357cf4]">
                  {workspace}
                </span>

                <button
                  type="button"
                  onClick={() => setModelModalOpen(true)}
                  disabled={!canRegisterDevices}
                  className="flex h-9 items-center gap-2 rounded-[4px] border border-[#357cf4] px-4 text-[11px] font-semibold text-[#357cf4] disabled:border-[#cfd8e7] disabled:text-[#9aacbf]"
                >
                  <Cpu className="h-4 w-4" />
                  Add Device Model
                </button>

                <button
                  type="button"
                  onClick={() => setStockModalOpen(true)}
                  disabled={!canRegisterDevices}
                  className="flex h-9 items-center gap-2 rounded-[4px] bg-[#357cf4] px-4 text-[11px] font-semibold text-white disabled:bg-[#b8c7dc]"
                >
                  <CirclePlus className="h-4 w-4" />
                  Add Device / Stock Intake
                </button>
              </div>
            </header>

            {success ? (
              <div className="mt-4 flex items-center gap-2 rounded-[4px] border border-emerald-200 bg-emerald-50 px-4 py-3 text-[11px] font-medium text-emerald-700">
                <CheckCircle2 className="h-4 w-4" />
                {success}
              </div>
            ) : null}

            {error ? (
              <div className="mt-4 rounded-[4px] border border-red-200 bg-red-50 px-4 py-3 text-[11px] font-medium text-red-700">
                {error}
              </div>
            ) : null}

            <div className="mt-5 grid gap-4 md:grid-cols-4">
              {[
                {
                  label: "Visible inventory",
                  value: statistics.total,
                  icon: Boxes,
                },
                {
                  label: "Platform stock",
                  value: statistics.platformStock,
                  icon: PackageCheck,
                },
                {
                  label: "Dealer stock",
                  value: statistics.dealerStock,
                  icon: Building2,
                },
                {
                  label: "Installed",
                  value: statistics.installed,
                  icon: ShieldCheck,
                },
              ].map((item) => (
                <article
                  key={item.label}
                  className="rounded-[6px] border border-[#dfe6ef] p-4"
                >
                  <div className="flex items-center justify-between">
                    <p className="text-[10px] font-semibold uppercase tracking-wide text-[#8b9ab4]">
                      {item.label}
                    </p>
                    <item.icon className="h-4 w-4 text-[#357cf4]" />
                  </div>
                  <p className="mt-2 text-[26px] font-semibold text-[#344b72]">
                    {item.value}
                  </p>
                </article>
              ))}
            </div>

            <section className="mt-5 overflow-hidden rounded-[6px] border border-[#dfe6ef]">
              <header className="flex flex-wrap items-center gap-3 border-b border-[#e2e8f1] px-5 py-4">
                <form
                  onSubmit={search}
                  className="flex min-w-[300px] flex-1"
                >
                  <div className="relative min-w-0 flex-1">
                    <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-[#8b9ab4]" />
                    <input
                      value={searchInput}
                      onChange={(event) =>
                        setSearchInput(event.target.value)
                      }
                      placeholder="Device code, IMEI, or serial number"
                      className="h-9 w-full rounded-l-[4px] border border-[#cfd8e7] pl-10 pr-3 text-[11px] outline-none focus:border-[#357cf4]"
                    />
                  </div>

                  <button
                    type="submit"
                    className="h-9 rounded-r-[4px] bg-[#52698e] px-4 text-[11px] font-semibold text-white"
                  >
                    Search
                  </button>
                </form>

                <select
                  value={deviceModelId}
                  onChange={(event) => {
                    setLoading(true);
                    setDeviceModelId(event.target.value);
                  }}
                  className="h-9 min-w-[210px] rounded-[4px] border border-[#cfd8e7] bg-white px-3 text-[11px] text-[#52698e]"
                >
                  <option value="">All Device Models</option>
                  {models.map((model) => (
                    <option key={model.id} value={model.id}>
                      {model.manufacturer} {model.modelName}
                    </option>
                  ))}
                </select>

                <select
                  value={lifecycleStatus}
                  onChange={(event) => {
                    setLoading(true);
                    setLifecycleStatus(event.target.value);
                  }}
                  className="h-9 min-w-[160px] rounded-[4px] border border-[#cfd8e7] bg-white px-3 text-[11px] text-[#52698e]"
                >
                  {lifecycleOptions.map((status) => (
                    <option key={status || "ALL"} value={status}>
                      {status
                        ? status.replaceAll("_", " ")
                        : "All lifecycle states"}
                    </option>
                  ))}
                </select>

                <button
                  type="button"
                  onClick={refresh}
                  disabled={loading}
                  className="flex h-9 items-center gap-2 rounded-[4px] border border-[#cfd8e7] px-4 text-[11px] font-semibold text-[#52698e]"
                >
                  <RefreshCw
                    className={[
                      "h-4 w-4",
                      loading ? "animate-spin" : "",
                    ].join(" ")}
                  />
                  Refresh
                </button>
              </header>

              {!canViewDevices ? (
                <div className="p-12 text-center text-[12px] text-[#71819c]">
                  This account does not have device.view permission.
                </div>
              ) : loading ? (
                <div className="flex min-h-[300px] items-center justify-center gap-2 text-[12px] text-[#71819c]">
                  <LoaderCircle className="h-5 w-5 animate-spin text-[#357cf4]" />
                  Loading scoped device inventory
                </div>
              ) : devices.length === 0 ? (
                <div className="grid min-h-[300px] place-items-center text-center">
                  <div>
                    <Boxes className="mx-auto h-10 w-10 text-[#b5c2d5]" />
                    <p className="mt-3 text-[12px] font-semibold text-[#52698e]">
                      No matching device inventory
                    </p>
                    <p className="mt-1 text-[10px] text-[#8b9ab4]">
                      Create a Device Model and receive the first
                      physical tracker.
                    </p>
                  </div>
                </div>
              ) : (
                <div className="overflow-x-auto">
                  <table className="w-full min-w-[1180px] text-left text-[10px]">
                    <thead className="bg-[#f4f7fb] text-[#52698e]">
                      <tr>
                        {[
                          "Device",
                          "IMEI",
                          "Serial",
                          "Model",
                          "Network",
                          "Lifecycle",
                          "Current custody",
                          "Received",
                          "Versions",
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
                      {devices.map((device) => {
                        const allocation =
                          device.dealerAllocations?.[0] ?? null;
                        const installed =
                          (device.vehicleAssignments?.length ?? 0) > 0 ||
                          device.lifecycleStatus === "INSTALLED";
                        const allocatable =
                          canAllocateDevices &&
                          !allocation &&
                          !installed &&
                          ["RECEIVED", "IN_STOCK"].includes(
                            device.lifecycleStatus,
                          );

                        return (
                          <tr
                            key={device.id}
                            className="border-t border-[#e2e8f1] text-[#52698e] hover:bg-[#f8faff]"
                          >
                            <td className="px-4 py-4">
                              <p className="font-semibold text-[#405779]">
                                {device.deviceCode}
                              </p>
                              <p className="mt-1 text-[9px] text-[#8b9ab4]">
                                {device.id.slice(0, 8)}
                              </p>
                            </td>

                            <td className="px-4 py-4 font-medium text-[#357cf4]">
                              {device.imei || "-"}
                            </td>

                            <td className="px-4 py-4">
                              {device.serialNumber || "-"}
                            </td>

                            <td className="px-4 py-4">
                              <p className="font-semibold text-[#405779]">
                                {device.deviceModel.manufacturer}{" "}
                                {device.deviceModel.modelName}
                              </p>
                              <p className="mt-1 text-[9px] text-[#8b9ab4]">
                                {device.deviceModel.modelCode}
                              </p>
                            </td>

                            <td className="px-4 py-4">
                              {device.deviceModel.networkType || "-"}
                            </td>

                            <td className="px-4 py-4">
                              <span
                                className={[
                                  "rounded-full px-2 py-1 text-[9px] font-semibold",
                                  statusClass(
                                    device.lifecycleStatus,
                                  ),
                                ].join(" ")}
                              >
                                {device.lifecycleStatus.replaceAll(
                                  "_",
                                  " ",
                                )}
                              </span>
                            </td>

                            <td className="px-4 py-4">
                              <p className="font-semibold text-[#405779]">
                                {custodyLabel(device)}
                              </p>
                              <p className="mt-1 text-[9px] text-[#8b9ab4]">
                                {allocation
                                  ? allocation.allocationCode ??
                                    "Dealer allocation"
                                  : "Platform custody"}
                              </p>
                            </td>

                            <td className="px-4 py-4">
                              {formatDate(
                                device.receivedAt ??
                                  device.createdAt,
                              )}
                            </td>

                            <td className="px-4 py-4">
                              <p>
                                HW {device.hardwareVersion || "-"}
                              </p>
                              <p className="mt-1">
                                FW {device.firmwareVersion || "-"}
                              </p>
                            </td>

                            <td className="px-4 py-4">
                              <button
                                type="button"
                                onClick={() =>
                                  setAllocationDevice(device)
                                }
                                disabled={!allocatable}
                                title={
                                  allocatable
                                    ? "Allocate this Platform stock device to a Dealer"
                                    : "Only unallocated Platform stock can be allocated"
                                }
                                className="flex h-8 items-center gap-2 rounded-[3px] bg-[#357cf4] px-3 text-[10px] font-semibold text-white disabled:bg-[#b8c7dc]"
                              >
                                <Building2 className="h-3.5 w-3.5" />
                                {allocation
                                  ? "Allocated"
                                  : installed
                                    ? "Installed"
                                    : "Allocate"}
                              </button>
                            </td>
                          </tr>
                        );
                      })}
                    </tbody>
                  </table>
                </div>
              )}
            </section>
          </div>
        </section>
      </div>

      {modelModalOpen ? (
        <AddDeviceModelModal
          onClose={() => setModelModalOpen(false)}
          onCreated={modelCreated}
        />
      ) : null}

      {stockModalOpen ? (
        <DeviceStockIntakeModal
          models={models}
          onClose={() => setStockModalOpen(false)}
          onCreated={deviceCreated}
          onCreateModel={() => {
            setStockModalOpen(false);
            setModelModalOpen(true);
          }}
        />
      ) : null}

      {allocationDevice ? (
        <AllocateDeviceModal
          device={allocationDevice}
          onClose={() => setAllocationDevice(null)}
          onAllocated={deviceAllocated}
        />
      ) : null}
    </>
  );
}