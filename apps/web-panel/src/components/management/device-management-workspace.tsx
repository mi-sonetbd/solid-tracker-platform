"use client";

import {
  CirclePlus,
  Cpu,
  FilePenLine,
  FileSpreadsheet,
  LoaderCircle,
  MoveRight,
  PackagePlus,
  RefreshCw,
  Search,
  ShieldCheck,
  Trash2,
  Unlink,
} from "lucide-react";
import {
  useEffect,
  useMemo,
  useState,
  type FormEvent,
  type ReactNode,
} from "react";
import { AddDeviceModelModal } from "@/components/management/add-device-model-modal";
import { BulkDeviceStockIntakeModal } from "@/components/management/bulk-device-stock-intake-modal";
import { DeviceSellMoveModal } from "@/components/management/device-sell-move-modal";
import { DeviceStockIntakeModal } from "@/components/management/device-stock-intake-modal";
import { ManagementMonitorAccountTree } from "@/components/management/management-monitor-account-tree";
import type {
  BulkDeviceRegistrationResult,
  DeviceListResponse,
  DeviceModelListResponse,
  DeviceModelSummary,
  DeviceSummary,
  TransferDevicesResult,
} from "@/lib/management/asset-types";
import type { CustomerSummary } from "@/lib/management/customer-types";
import type {
  DealerSummary,
  ManagementApiError,
} from "@/lib/management/dealer-types";
import {
  customerDisplayName,
  type ManagementMonitorScope,
} from "@/lib/management/monitor-types";
import { useManagementMonitorHierarchy } from "@/lib/management/use-management-monitor-hierarchy";

type DeviceManagementWorkspaceProps = {
  workspace: string;
  canViewDevices: boolean;
  canViewDealers: boolean;
  canViewCustomers: boolean;
  canRegisterDevices: boolean;
  canTransferDevices: boolean;
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

function normalizeDevice(device: DeviceSummary): DeviceSummary {
  return {
    ...device,
    dealerAllocations: device.dealerAllocations ?? [],
    vehicleAssignments: device.vehicleAssignments ?? [],
    ownershipHistory: device.ownershipHistory ?? [],
    custodyHistory: device.custodyHistory ?? [],
  };
}

function formatDate(value?: string | null) {
  if (!value) return "-";

  const date = new Date(value);

  if (Number.isNaN(date.getTime())) return "-";

  return new Intl.DateTimeFormat("en-GB", {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(date);
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

function accountLabel(
  device: DeviceSummary,
  dealers: DealerSummary[],
  customers: CustomerSummary[],
) {
  const customerId =
    device.vehicleAssignments?.[0]?.vehicle?.customerId ??
    device.ownershipHistory?.[0]?.ownerCustomerId ??
    device.custodyHistory?.[0]?.custodianCustomerId ??
    null;

  if (customerId) {
    const customer = customers.find(
      (item) => item.id === customerId,
    );

    if (customer) {
      return customerDisplayName(customer);
    }
  }

  const dealerId =
    device.dealerAllocations?.[0]?.dealerOrganizationId ??
    device.ownershipHistory?.[0]?.ownerOrganizationId ??
    device.custodyHistory?.[0]?.custodianOrganizationId ??
    null;

  if (dealerId) {
    const dealer = dealers.find(
      (item) => item.id === dealerId,
    );

    if (dealer) return dealer.name;
  }

  return "Solid Tracker Platform";
}

function ActionButton({
  icon,
  label,
  onClick,
  disabled = false,
  title,
}: {
  icon: ReactNode;
  label: string;
  onClick?: () => void;
  disabled?: boolean;
  title?: string;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      title={title}
      className="flex h-8 items-center gap-1.5 rounded-[3px] border border-[#cfd8e7] bg-white px-3 text-[10px] font-semibold text-[#52698e] shadow-sm hover:border-[#9fb7dc] disabled:cursor-not-allowed disabled:bg-[#f2f5f9] disabled:text-[#a4afc0]"
    >
      {icon}
      {label}
    </button>
  );
}

export function DeviceManagementWorkspace({
  workspace,
  canViewDevices,
  canViewDealers,
  canViewCustomers,
  canRegisterDevices,
  canTransferDevices,
}: DeviceManagementWorkspaceProps) {
  const [selectedScope, setSelectedScope] =
    useState<ManagementMonitorScope>({
      key: "platform",
      type: "PLATFORM",
      id: null,
      label: "Visible Inventory",
    });
  const [devices, setDevices] = useState<DeviceSummary[]>([]);
  const [models, setModels] = useState<DeviceModelSummary[]>([]);
  const [loading, setLoading] = useState(canViewDevices);
  const [error, setError] = useState("");
  const [success, setSuccess] = useState("");
  const [imeiInput, setImeiInput] = useState("");
  const [nameInput, setNameInput] = useState("");
  const [activeSearch, setActiveSearch] = useState("");
  const [lifecycleStatus, setLifecycleStatus] = useState("");
  const [deviceModelId, setDeviceModelId] = useState("");
  const [page, setPage] = useState(1);
  const [pageSize, setPageSize] = useState(25);
  const [total, setTotal] = useState(0);
  const [totalPages, setTotalPages] = useState(1);
  const [refreshVersion, setRefreshVersion] = useState(0);
  const [modelRefreshVersion, setModelRefreshVersion] =
    useState(0);
  const [selectedIds, setSelectedIds] =
    useState<Set<string>>(new Set());
  const [modelModalOpen, setModelModalOpen] = useState(false);
  const [stockModalOpen, setStockModalOpen] = useState(false);
  const [bulkModalOpen, setBulkModalOpen] = useState(false);
  const [transferModalOpen, setTransferModalOpen] =
    useState(false);

  const hierarchy = useManagementMonitorHierarchy({
    canViewDealers,
    canViewCustomers,
  });

  useEffect(() => {
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

        setModels(
          (payload as DeviceModelListResponse).items,
        );
      })
      .catch((requestError: unknown) => {
        if (
          controller.signal.aborted ||
          (requestError instanceof DOMException &&
            requestError.name === "AbortError")
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
  }, [modelRefreshVersion]);

  useEffect(() => {
    if (!canViewDevices) return;

    const controller = new AbortController();
    const parameters = new URLSearchParams({
      page: String(page),
      pageSize: String(pageSize),
    });

    if (activeSearch) {
      parameters.set("search", activeSearch);
    }
    if (lifecycleStatus) {
      parameters.set("lifecycleStatus", lifecycleStatus);
    }
    if (deviceModelId) {
      parameters.set("deviceModelId", deviceModelId);
    }

    if (
      selectedScope.type === "DEALER" &&
      selectedScope.id
    ) {
      parameters.set(
        "dealerOrganizationId",
        selectedScope.id,
      );
    } else if (
      selectedScope.type === "CUSTOMER" &&
      selectedScope.id
    ) {
      parameters.set("customerId", selectedScope.id);
    } else if (selectedScope.type === "DIRECT") {
      parameters.set("directCustomers", "true");
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
              : "Scoped Device loading failed.",
          );
        }

        const result = payload as DeviceListResponse;

        setDevices(result.items.map(normalizeDevice));
        setTotal(result.total);
        setTotalPages(Math.max(result.totalPages, 1));
        setSelectedIds(new Set());
        setError("");
      })
      .catch((requestError: unknown) => {
        if (
          controller.signal.aborted ||
          (requestError instanceof DOMException &&
            requestError.name === "AbortError")
        ) {
          return;
        }

        setDevices([]);
        setTotal(0);
        setTotalPages(1);
        setError(
          requestError instanceof Error
            ? requestError.message
            : "Scoped Device loading failed.",
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
    page,
    pageSize,
    refreshVersion,
    selectedScope,
  ]);

  const selectedDevices = useMemo(
    () =>
      devices.filter((device) =>
        selectedIds.has(device.id),
      ),
    [devices, selectedIds],
  );

  const transferBlocked = selectedDevices.some(
    (device) =>
      (device.vehicleAssignments?.length ?? 0) > 0 ||
      !["RECEIVED", "IN_STOCK", "ALLOCATED"].includes(
        device.lifecycleStatus,
      ),
  );

  const allSelected =
    devices.length > 0 &&
    devices.every((device) => selectedIds.has(device.id));

  function prepareReload() {
    setLoading(true);
    setError("");
    setSuccess("");
  }

  function reloadDevices() {
    prepareReload();
    setRefreshVersion((current) => current + 1);
  }

  function selectScope(scope: ManagementMonitorScope) {
    prepareReload();
    setSelectedScope(scope);
    setPage(1);
  }

  function search(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    prepareReload();
    setActiveSearch(
      imeiInput.trim() || nameInput.trim(),
    );
    setPage(1);
  }

  function resetFilters() {
    prepareReload();
    setImeiInput("");
    setNameInput("");
    setActiveSearch("");
    setLifecycleStatus("");
    setDeviceModelId("");
    setPage(1);
  }

  function toggleAll() {
    setSelectedIds(() => {
      if (allSelected) return new Set();

      return new Set(devices.map((device) => device.id));
    });
  }

  function toggleDevice(deviceId: string) {
    setSelectedIds((current) => {
      const next = new Set(current);

      if (next.has(deviceId)) {
        next.delete(deviceId);
      } else {
        next.add(deviceId);
      }

      return next;
    });
  }

  function openSingleTransfer(device: DeviceSummary) {
    const blocked =
      (device.vehicleAssignments?.length ?? 0) > 0 ||
      !["RECEIVED", "IN_STOCK", "ALLOCATED"].includes(
        device.lifecycleStatus,
      );

    if (blocked) {
      setError(
        "Installed or lifecycle-blocked Devices must be removed or returned before transfer.",
      );
      return;
    }

    setSelectedIds(new Set([device.id]));
    setTransferModalOpen(true);
    setError("");
  }

  function modelCreated(model: DeviceModelSummary) {
    setModels((current) => [model, ...current]);
    setModelModalOpen(false);
    setSuccess(
      `Device Model ${model.manufacturer} ${model.modelName} created.`,
    );
  }

  function deviceCreated(device: DeviceSummary) {
    setStockModalOpen(false);
    setSuccess(
      `Device ${device.deviceCode} received into Platform stock.`,
    );
    setModelRefreshVersion((current) => current + 1);
    reloadDevices();
  }

  function bulkCompleted(
    result: BulkDeviceRegistrationResult,
  ) {
    setSuccess(
      `Bulk intake completed: ${result.created} created, ${result.failed} rejected.`,
    );
    setModelRefreshVersion((current) => current + 1);
    reloadDevices();
  }

  function transferCompleted(
    result: TransferDevicesResult,
  ) {
    setTransferModalOpen(false);
    setSuccess(
      `${result.total} Device(s) moved to the selected ${result.targetType.toLowerCase()}.`,
    );
    hierarchy.refresh();
    reloadDevices();
  }

  if (!canViewDevices) {
    return (
      <div className="grid min-h-[calc(100vh-var(--st-topbar-height))] place-items-center bg-[#f1f4f8] p-6">
        <section className="max-w-lg rounded-[6px] border border-[#dfe6ef] bg-white p-8 text-center">
          <ShieldCheck className="mx-auto h-10 w-10 text-[#357cf4]" />
          <h1 className="mt-4 text-[18px] font-semibold text-[#2b4065]">
            Device access is restricted
          </h1>
          <p className="mt-2 text-[11px] leading-6 text-[#71819c]">
            This authenticated account does not have device.view permission.
          </p>
        </section>
      </div>
    );
  }

  return (
    <>
      <div className="flex h-[calc(100vh-var(--st-topbar-height))] min-h-[640px] overflow-hidden bg-[#f1f4f8]">
        <ManagementMonitorAccountTree
          workspace={workspace}
          dealers={hierarchy.dealers}
          customers={hierarchy.customers}
          loading={hierarchy.loading}
          error={hierarchy.error}
          selectedScope={selectedScope}
          onSelectScope={selectScope}
          onRefresh={() => {
            hierarchy.refresh();
            reloadDevices();
          }}
        />

        <main className="st-scrollbar min-w-0 flex-1 overflow-auto p-3">
          <section className="min-h-full rounded-[4px] border border-[#dfe6ef] bg-white">
            <header className="flex flex-wrap items-center gap-2 border-b border-[#e2e8f1] px-4 py-3">
              <div className="mr-auto">
                <p className="text-[9px] font-semibold uppercase tracking-[0.12em] text-[#8b9ab4]">
                  {selectedScope.label}
                </p>
                <h1 className="mt-1 text-[14px] font-semibold text-[#344b72]">
                  Device Management
                </h1>
              </div>

              <ActionButton
                icon={<PackagePlus className="h-3.5 w-3.5" />}
                label="Import device"
                onClick={() => setBulkModalOpen(true)}
                disabled={!canRegisterDevices}
                title={
                  canRegisterDevices
                    ? "Bulk import one Device Model with multiple IMEIs"
                    : "Platform device.register permission is required"
                }
              />
              <ActionButton
                icon={<FilePenLine className="h-3.5 w-3.5" />}
                label="Edit device"
                disabled
                title="Controlled metadata editing will be connected in a later workflow"
              />
              <ActionButton
                icon={<MoveRight className="h-3.5 w-3.5" />}
                label="Sell/move"
                onClick={() => setTransferModalOpen(true)}
                disabled={
                  !canTransferDevices ||
                  selectedDevices.length === 0 ||
                  transferBlocked
                }
                title={
                  transferBlocked
                    ? "Installed or lifecycle-blocked Devices cannot be moved"
                    : "Move selected Devices to a scoped Dealer or Customer"
                }
              />
              <ActionButton
                icon={<FileSpreadsheet className="h-3.5 w-3.5" />}
                label="Expire/Edit due"
                disabled
                title="Subscription due-date editing is not part of this asset stage"
              />
              <ActionButton
                icon={<FileSpreadsheet className="h-3.5 w-3.5" />}
                label="Create/Edit invoice"
                disabled
                title="Invoice workflow remains in Billing"
              />
              <ActionButton
                icon={<Trash2 className="h-3.5 w-3.5" />}
                label="Delete device"
                disabled
                title="Physical Device history is retained; destructive delete is disabled"
              />
              <ActionButton
                icon={<Unlink className="h-3.5 w-3.5" />}
                label="Unbind"
                disabled
                title="Installed trackers must use the explicit removal workflow"
              />

              {canRegisterDevices ? (
                <>
                  <ActionButton
                    icon={<Cpu className="h-3.5 w-3.5" />}
                    label="Add Device Model"
                    onClick={() => setModelModalOpen(true)}
                  />
                  <ActionButton
                    icon={<CirclePlus className="h-3.5 w-3.5" />}
                    label="Add Device / Stock Intake"
                    onClick={() => setStockModalOpen(true)}
                  />
                </>
              ) : null}
            </header>

            <form
              onSubmit={search}
              className="grid gap-3 border-b border-[#e2e8f1] bg-[#fbfcfe] p-4 md:grid-cols-2 xl:grid-cols-6"
            >
              <label className="text-[9px] font-semibold text-[#71819c]">
                IMEI
                <input
                  value={imeiInput}
                  onChange={(event) =>
                    setImeiInput(event.target.value)
                  }
                  className="mt-1 h-9 w-full rounded-[3px] border border-[#cfd8e7] bg-white px-3 text-[10px] outline-none"
                  placeholder="Search IMEI"
                />
              </label>

              <label className="text-[9px] font-semibold text-[#71819c]">
                Device name / code
                <input
                  value={nameInput}
                  onChange={(event) =>
                    setNameInput(event.target.value)
                  }
                  className="mt-1 h-9 w-full rounded-[3px] border border-[#cfd8e7] bg-white px-3 text-[10px] outline-none"
                  placeholder="Search Device"
                />
              </label>

              <label className="text-[9px] font-semibold text-[#71819c]">
                Device Model
                <select
                  value={deviceModelId}
                  onChange={(event) => {
                    prepareReload();
                    setDeviceModelId(event.target.value);
                    setPage(1);
                  }}
                  className="mt-1 h-9 w-full rounded-[3px] border border-[#cfd8e7] bg-white px-3 text-[10px] outline-none"
                >
                  <option value="">All models</option>
                  {models.map((model) => (
                    <option key={model.id} value={model.id}>
                      {model.manufacturer} {model.modelName}
                    </option>
                  ))}
                </select>
              </label>

              <label className="text-[9px] font-semibold text-[#71819c]">
                Lifecycle
                <select
                  value={lifecycleStatus}
                  onChange={(event) => {
                    prepareReload();
                    setLifecycleStatus(event.target.value);
                    setPage(1);
                  }}
                  className="mt-1 h-9 w-full rounded-[3px] border border-[#cfd8e7] bg-white px-3 text-[10px] outline-none"
                >
                  {lifecycleOptions.map((status) => (
                    <option key={status || "ALL"} value={status}>
                      {status
                        ? status.replaceAll("_", " ")
                        : "All statuses"}
                    </option>
                  ))}
                </select>
              </label>

              <button
                type="submit"
                className="mt-4 flex h-9 items-center justify-center gap-2 rounded-[3px] bg-[#357cf4] px-4 text-[10px] font-semibold text-white"
              >
                <Search className="h-3.5 w-3.5" />
                Search
              </button>

              <button
                type="button"
                onClick={resetFilters}
                className="mt-4 flex h-9 items-center justify-center gap-2 rounded-[3px] border border-[#cfd8e7] bg-white px-4 text-[10px] font-semibold text-[#52698e]"
              >
                <RefreshCw className="h-3.5 w-3.5" />
                Reset
              </button>
            </form>

            {success ? (
              <p className="mx-4 mt-4 rounded-[4px] bg-emerald-50 px-4 py-3 text-[10px] font-medium text-emerald-700">
                {success}
              </p>
            ) : null}

            {error ? (
              <p className="mx-4 mt-4 rounded-[4px] bg-red-50 px-4 py-3 text-[10px] font-medium text-red-700">
                {error}
              </p>
            ) : null}

            <div className="overflow-x-auto">
              <table className="w-full min-w-[1160px] text-left text-[10px]">
                <thead className="bg-[#f7f9fc] text-[9px] font-semibold uppercase tracking-[0.04em] text-[#71819c]">
                  <tr>
                    <th className="w-10 px-3 py-3">
                      <input
                        type="checkbox"
                        checked={allSelected}
                        onChange={toggleAll}
                        aria-label="Select current Device page"
                      />
                    </th>
                    <th className="px-3 py-3">No.</th>
                    <th className="px-3 py-3">Account</th>
                    <th className="px-3 py-3">Device name</th>
                    <th className="px-3 py-3">IMEI</th>
                    <th className="px-3 py-3">Device Model</th>
                    <th className="px-3 py-3">Activated</th>
                    <th className="px-3 py-3">Subscription</th>
                    <th className="px-3 py-3">Expiration</th>
                    <th className="px-3 py-3">Status</th>
                    <th className="px-3 py-3">Actions</th>
                  </tr>
                </thead>

                <tbody>
                  {loading ? (
                    <tr>
                      <td colSpan={11} className="py-20 text-center">
                        <LoaderCircle className="mx-auto h-6 w-6 animate-spin text-[#357cf4]" />
                        <p className="mt-3 text-[#71819c]">
                          Loading scoped Devices
                        </p>
                      </td>
                    </tr>
                  ) : devices.length === 0 ? (
                    <tr>
                      <td colSpan={11} className="py-20 text-center text-[#8b9ab4]">
                        No Device exists in the selected hierarchy scope.
                      </td>
                    </tr>
                  ) : (
                    devices.map((device, index) => (
                      <tr
                        key={device.id}
                        className="border-b border-[#edf1f6] text-[#52698e] hover:bg-[#fbfdff]"
                      >
                        <td className="px-3 py-3">
                          <input
                            type="checkbox"
                            checked={selectedIds.has(device.id)}
                            onChange={() => toggleDevice(device.id)}
                            aria-label={`Select ${device.deviceCode}`}
                          />
                        </td>
                        <td className="px-3 py-3">
                          {(page - 1) * pageSize + index + 1}
                        </td>
                        <td className="max-w-[190px] truncate px-3 py-3 font-medium text-[#344b72]">
                          {accountLabel(
                            device,
                            hierarchy.dealers,
                            hierarchy.customers,
                          )}
                        </td>
                        <td className="px-3 py-3 text-[#357cf4]">
                          {device.deviceCode}
                        </td>
                        <td className="px-3 py-3 font-mono">
                          {device.imei || "-"}
                        </td>
                        <td className="px-3 py-3">
                          {device.deviceModel.manufacturer}{" "}
                          {device.deviceModel.modelName}
                        </td>
                        <td className="px-3 py-3">
                          {formatDate(
                            device.receivedAt ?? device.createdAt,
                          )}
                        </td>
                        <td className="px-3 py-3">-</td>
                        <td className="px-3 py-3">-</td>
                        <td className="px-3 py-3">
                          <span
                            className={[
                              "rounded-full px-2 py-1 text-[8px] font-semibold",
                              statusClass(device.lifecycleStatus),
                            ].join(" ")}
                          >
                            {device.lifecycleStatus.replaceAll("_", " ")}
                          </span>
                        </td>
                        <td className="px-3 py-3">
                          <button
                            type="button"
                            onClick={() => openSingleTransfer(device)}
                            disabled={
                              !canTransferDevices ||
                              (device.vehicleAssignments?.length ?? 0) > 0 ||
                              ![
                                "RECEIVED",
                                "IN_STOCK",
                                "ALLOCATED",
                              ].includes(device.lifecycleStatus)
                            }
                            aria-label={`Sell or move ${device.deviceCode}`}
                            title="Sell or move this Device"
                            className="inline-flex h-7 items-center gap-1 rounded-[3px] border border-[#357cf4] px-2 text-[9px] font-semibold text-[#357cf4] hover:bg-[#357cf4] hover:text-white disabled:cursor-not-allowed disabled:border-[#cbd5e1] disabled:text-[#a4afc0] disabled:hover:bg-transparent"
                          >
                            <MoveRight className="h-3 w-3" />
                            Sell/move
                          </button>
                        </td>
                      </tr>
                    ))
                  )}
                </tbody>
              </table>
            </div>

            <footer className="flex flex-wrap items-center justify-between gap-3 border-t border-[#e2e8f1] px-4 py-3 text-[10px] text-[#71819c]">
              <span>
                Selected {selectedDevices.length} Â· Showing{" "}
                {devices.length} of {total} Device(s)
              </span>

              <div className="flex items-center gap-2">
                <label>
                  Page size{" "}
                  <select
                    value={pageSize}
                    onChange={(event) => {
                      prepareReload();
                      setPageSize(Number(event.target.value));
                      setPage(1);
                    }}
                    className="h-8 rounded-[3px] border border-[#cfd8e7] bg-white px-2"
                  >
                    <option value={25}>25</option>
                    <option value={50}>50</option>
                    <option value={100}>100</option>
                  </select>
                </label>

                <button
                  type="button"
                  disabled={page <= 1 || loading}
                  onClick={() => {
                    prepareReload();
                    setPage((current) => Math.max(1, current - 1));
                  }}
                  className="h-8 rounded-[3px] border border-[#cfd8e7] bg-white px-3 font-semibold disabled:opacity-40"
                >
                  Previous
                </button>

                <span>
                  Page {page} / {totalPages}
                </span>

                <button
                  type="button"
                  disabled={page >= totalPages || loading}
                  onClick={() => {
                    prepareReload();
                    setPage((current) =>
                      Math.min(totalPages, current + 1),
                    );
                  }}
                  className="h-8 rounded-[3px] border border-[#cfd8e7] bg-white px-3 font-semibold disabled:opacity-40"
                >
                  Next
                </button>
              </div>
            </footer>
          </section>
        </main>
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

      {bulkModalOpen ? (
        <BulkDeviceStockIntakeModal
          models={models}
          onClose={() => setBulkModalOpen(false)}
          onCompleted={bulkCompleted}
        />
      ) : null}

      {transferModalOpen ? (
        <DeviceSellMoveModal
          selectedDevices={selectedDevices}
          availableDevices={devices}
          dealers={hierarchy.dealers}
          customers={hierarchy.customers}
          onClose={() => setTransferModalOpen(false)}
          onCompleted={transferCompleted}
        />
      ) : null}
    </>
  );
}