"use client";

import {
  Building2,
  ChevronDown,
  ChevronRight,
  LoaderCircle,
  Search,
  Trash2,
  UserRound,
  UsersRound,
  X,
} from "lucide-react";
import {
  useMemo,
  useState,
  type FormEvent,
} from "react";
import type {
  DeviceSummary,
  TransferDevicesInput,
  TransferDevicesResult,
} from "@/lib/management/asset-types";
import type { CustomerSummary } from "@/lib/management/customer-types";
import type {
  DealerSummary,
  ManagementApiError,
} from "@/lib/management/dealer-types";
import { customerDisplayName } from "@/lib/management/monitor-types";

type DeviceSellMoveModalProps = {
  selectedDevices: DeviceSummary[];
  availableDevices: DeviceSummary[];
  dealers: DealerSummary[];
  customers: CustomerSummary[];
  onClose: () => void;
  onCompleted: (
    result: TransferDevicesResult,
  ) => void;
};

type DestinationNode = {
  key: string;
  label: string;
  count: number;
  targetType?: "DEALER" | "CUSTOMER";
  targetId?: string;
  children: DestinationNode[];
};

function deviceAccountLabel(
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

    if (customer) return customerDisplayName(customer);
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

function createDestinationTree(
  dealers: DealerSummary[],
  customers: CustomerSummary[],
): DestinationNode[] {
  const directCustomers = customers
    .filter(
      (customer) => customer.managingDealerId === null,
    )
    .sort((left, right) =>
      customerDisplayName(left).localeCompare(
        customerDisplayName(right),
      ),
    )
    .map((customer) => ({
      key: `customer:${customer.id}`,
      label: customerDisplayName(customer),
      count: customer._count?.vehicles ?? 0,
      targetType: "CUSTOMER" as const,
      targetId: customer.id,
      children: [],
    }));

  const dealerNodes = dealers
    .slice()
    .sort((left, right) =>
      left.name.localeCompare(right.name),
    )
    .map((dealer) => {
      const dealerCustomers = customers
        .filter(
          (customer) =>
            customer.managingDealerId === dealer.id,
        )
        .sort((left, right) =>
          customerDisplayName(left).localeCompare(
            customerDisplayName(right),
          ),
        )
        .map((customer) => ({
          key: `customer:${customer.id}`,
          label: customerDisplayName(customer),
          count: customer._count?.vehicles ?? 0,
          targetType: "CUSTOMER" as const,
          targetId: customer.id,
          children: [],
        }));

      return {
        key: `dealer:${dealer.id}`,
        label: dealer.name,
        count: dealerCustomers.length,
        targetType: "DEALER" as const,
        targetId: dealer.id,
        children: dealerCustomers,
      };
    });

  return [
    {
      key: "root:solid-tracker",
      label: "Solid Tracker",
      count: customers.length,
      children: [
        {
          key: "group:direct",
          label: "Direct Customers",
          count: directCustomers.length,
          children: directCustomers,
        },
        {
          key: "group:dealers",
          label: "Dealers",
          count: dealerNodes.length,
          children: dealerNodes,
        },
      ],
    },
  ];
}

function filterDestinationTree(
  nodes: DestinationNode[],
  query: string,
): DestinationNode[] {
  if (!query) return nodes;

  return nodes.flatMap((node) => {
    const children = filterDestinationTree(
      node.children,
      query,
    );
    const matches = node.label
      .toLowerCase()
      .includes(query);

    if (!matches && children.length === 0) {
      return [];
    }

    return [
      {
        ...node,
        children,
      },
    ];
  });
}

function collectExpandableKeys(
  nodes: DestinationNode[],
) {
  const keys: string[] = [];

  for (const node of nodes) {
    if (node.children.length > 0) {
      keys.push(node.key);
      keys.push(...collectExpandableKeys(node.children));
    }
  }

  return keys;
}

function DestinationTree({
  nodes,
  level,
  expanded,
  selectedKey,
  onToggle,
  onSelect,
}: {
  nodes: DestinationNode[];
  level: number;
  expanded: Set<string>;
  selectedKey: string;
  onToggle: (key: string) => void;
  onSelect: (node: DestinationNode) => void;
}) {
  return (
    <div>
      {nodes.map((node) => {
        const hasChildren = node.children.length > 0;
        const isExpanded = expanded.has(node.key);
        const selectable = Boolean(
          node.targetType && node.targetId,
        );
        const selected = selectedKey === node.key;
        const Icon = node.targetType === "CUSTOMER"
          ? UserRound
          : node.targetType === "DEALER"
            ? Building2
            : UsersRound;

        return (
          <div key={node.key}>
            <div
              className={[
                "flex min-h-9 items-center rounded-[3px]",
                selected
                  ? "bg-[#162b4d] text-white"
                  : "text-[#d4dceb] hover:bg-white/5",
              ].join(" ")}
              style={{
                paddingLeft: `${8 + level * 18}px`,
              }}
            >
              <button
                type="button"
                onClick={() => {
                  if (hasChildren) onToggle(node.key);
                }}
                disabled={!hasChildren}
                className="grid h-9 w-7 shrink-0 place-items-center disabled:opacity-30"
                aria-label={
                  hasChildren
                    ? `${isExpanded ? "Collapse" : "Expand"} ${node.label}`
                    : undefined
                }
              >
                {hasChildren ? (
                  isExpanded ? (
                    <ChevronDown className="h-3.5 w-3.5" />
                  ) : (
                    <ChevronRight className="h-3.5 w-3.5" />
                  )
                ) : (
                  <span className="h-1 w-1 rounded-full bg-[#71819c]" />
                )}
              </button>

              <button
                type="button"
                disabled={!selectable}
                onClick={() => onSelect(node)}
                className="flex min-w-0 flex-1 items-center gap-2 py-2 pr-3 text-left disabled:cursor-default"
              >
                <Icon
                  className={[
                    "h-4 w-4 shrink-0",
                    node.targetType === "CUSTOMER"
                      ? "text-[#29a8ef]"
                      : "text-[#ff9b24]",
                  ].join(" ")}
                />
                <span className="min-w-0 flex-1 truncate text-[11px] font-medium">
                  {node.label}
                </span>
                <span className="shrink-0 text-[9px] text-[#8090aa]">
                  ({node.count})
                </span>
              </button>
            </div>

            {hasChildren && isExpanded ? (
              <DestinationTree
                nodes={node.children}
                level={level + 1}
                expanded={expanded}
                selectedKey={selectedKey}
                onToggle={onToggle}
                onSelect={onSelect}
              />
            ) : null}
          </div>
        );
      })}
    </div>
  );
}

export function DeviceSellMoveModal({
  selectedDevices,
  availableDevices,
  dealers,
  customers,
  onClose,
  onCompleted,
}: DeviceSellMoveModalProps) {
  const tree = useMemo(
    () => createDestinationTree(dealers, customers),
    [customers, dealers],
  );
  const [selectedIds, setSelectedIds] = useState(
    () => new Set(selectedDevices.map((device) => device.id)),
  );
  const [expanded, setExpanded] = useState(
    () => new Set(collectExpandableKeys(tree)),
  );
  const [selectedKey, setSelectedKey] = useState("");
  const [targetType, setTargetType] = useState<
    "DEALER" | "CUSTOMER" | ""
  >("");
  const [targetId, setTargetId] = useState("");
  const [targetLabel, setTargetLabel] = useState("");
  const [imeiInput, setImeiInput] = useState("");
  const [destinationQuery, setDestinationQuery] =
    useState("");
  const [notes, setNotes] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState("");

  const devices = useMemo(
    () =>
      availableDevices.filter((device) =>
        selectedIds.has(device.id),
      ),
    [availableDevices, selectedIds],
  );

  const filteredTree = useMemo(
    () =>
      filterDestinationTree(
        tree,
        destinationQuery.trim().toLowerCase(),
      ),
    [destinationQuery, tree],
  );

  function removeDevice(deviceId: string) {
    setSelectedIds((current) => {
      const next = new Set(current);
      next.delete(deviceId);
      return next;
    });
  }

  function addByImei() {
    const requestedImeis = imeiInput
      .split(/[\r\n,]+/)
      .map((value) => value.trim())
      .filter(Boolean);

    if (requestedImeis.length === 0) return;

    const matchingDevices = availableDevices.filter(
      (device) =>
        Boolean(
          device.imei && requestedImeis.includes(device.imei),
        ),
    );
    const foundImeis = new Set(
      matchingDevices
        .map((device) => device.imei)
        .filter((value): value is string => Boolean(value)),
    );
    const missingImeis = requestedImeis.filter(
      (imei) => !foundImeis.has(imei),
    );

    setSelectedIds((current) => {
      const next = new Set(current);

      for (const device of matchingDevices) {
        next.add(device.id);
      }

      return next;
    });

    setImeiInput("");
    setError(
      missingImeis.length > 0
        ? `Not found on the loaded scoped page: ${missingImeis.join(", ")}`
        : "",
    );
  }

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError("");

    if (devices.length === 0) {
      setError("Select at least one Device.");
      return;
    }

    const blocked = devices.some(
      (device) =>
        (device.vehicleAssignments?.length ?? 0) > 0 ||
        !["RECEIVED", "IN_STOCK", "ALLOCATED"].includes(
          device.lifecycleStatus,
        ),
    );

    if (blocked) {
      setError(
        "Installed or lifecycle-blocked Devices must be removed or returned before transfer.",
      );
      return;
    }

    if (!targetType || !targetId) {
      setError("Select a destination Dealer or Customer.");
      return;
    }

    const input: TransferDevicesInput = {
      deviceIds: devices.map((device) => device.id),
      targetType,
      targetId,
      notes: notes.trim() || undefined,
    };

    setSubmitting(true);

    try {
      const response = await fetch(
        "/api/management/devices/transfer",
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
          },
          body: JSON.stringify(input),
        },
      );

      const payload = (await response.json()) as
        | TransferDevicesResult
        | ManagementApiError;

      if (!response.ok) {
        setError(
          "message" in payload
            ? payload.message
            : "Device transfer failed.",
        );
        return;
      }

      onCompleted(payload as TransferDevicesResult);
    } catch {
      setError(
        "The web panel could not reach the Device transfer service.",
      );
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div
      className="fixed inset-0 z-[2700] grid place-items-center bg-black/70 p-5"
      role="presentation"
      onMouseDown={(event) => {
        if (
          event.target === event.currentTarget &&
          !submitting
        ) {
          onClose();
        }
      }}
    >
      <section
        role="dialog"
        aria-modal="true"
        aria-labelledby="device-sell-move-title"
        className="flex max-h-[94vh] w-full max-w-[1160px] flex-col overflow-hidden rounded-[4px] border border-[#313b4b] bg-[#11151b] text-[#d8dfeb] shadow-[0_30px_90px_rgba(0,0,0,0.55)]"
      >
        <header className="flex h-14 items-center justify-between border-b border-[#303846] px-6">
          <h2
            id="device-sell-move-title"
            className="text-[17px] font-semibold text-white"
          >
            Sell/move
          </h2>
          <button
            type="button"
            onClick={onClose}
            disabled={submitting}
            aria-label="Close Device transfer"
            className="text-[#8390a4] hover:text-white disabled:opacity-50"
          >
            <X className="h-5 w-5" />
          </button>
        </header>

        <form
          onSubmit={submit}
          className="st-scrollbar overflow-y-auto p-6"
        >
          <div className="grid gap-5 lg:grid-cols-2">
            <section>
              <h3 className="text-[15px] font-semibold text-[#aebed5]">
                Selected device: {" "}
                <span className="text-[#ff404d]">
                  {devices.length}
                </span>
              </h3>

              <div className="mt-4 flex min-h-11 overflow-hidden rounded-[3px] border border-[#3a4454] bg-[#151a21]">
                <textarea
                  value={imeiInput}
                  onChange={(event) =>
                    setImeiInput(event.target.value)
                  }
                  rows={1}
                  className="min-h-11 min-w-0 flex-1 resize-y bg-transparent px-4 py-3 text-[11px] text-white outline-none placeholder:text-[#667287]"
                  placeholder="IMEI (one or multiple lines from the loaded page)"
                />
                <button
                  type="button"
                  onClick={addByImei}
                  className="w-24 bg-[#075ee8] text-[11px] font-semibold text-white hover:bg-[#0a67f4]"
                >
                  Add
                </button>
              </div>

              <div className="mt-4 min-h-[420px] overflow-hidden rounded-[3px] border border-[#303846] bg-[#10141a]">
                <div className="grid grid-cols-[1.25fr_1fr_1.1fr_70px] border-b border-[#303846] bg-[#171c23] text-[10px] font-semibold text-[#aebed5]">
                  <span className="px-4 py-4">IMEI</span>
                  <span className="border-l border-[#303846] px-4 py-4">
                    Device name
                  </span>
                  <span className="border-l border-[#303846] px-4 py-4">
                    Account
                  </span>
                  <span className="border-l border-[#303846] px-4 py-4 text-center">
                    Actions
                  </span>
                </div>

                <div className="st-scrollbar max-h-[365px] overflow-y-auto">
                  {devices.map((device) => (
                    <div
                      key={device.id}
                      className="grid grid-cols-[1.25fr_1fr_1.1fr_70px] border-b border-[#272f3b] text-[10px] text-[#d5dce7]"
                    >
                      <span className="break-all px-4 py-4 font-mono text-[#74a7ff]">
                        {device.imei || "-"}
                      </span>
                      <span className="border-l border-[#272f3b] px-4 py-4 font-medium">
                        {device.deviceCode}
                      </span>
                      <span className="border-l border-[#272f3b] px-4 py-4">
                        {deviceAccountLabel(
                          device,
                          dealers,
                          customers,
                        )}
                      </span>
                      <span className="grid place-items-center border-l border-[#272f3b]">
                        <button
                          type="button"
                          onClick={() => removeDevice(device.id)}
                          aria-label={`Remove ${device.deviceCode}`}
                          className="text-[#357cf4] hover:text-red-400"
                        >
                          <Trash2 className="h-4 w-4" />
                        </button>
                      </span>
                    </div>
                  ))}

                  {devices.length === 0 ? (
                    <p className="px-4 py-12 text-center text-[10px] text-[#71819c]">
                      No Device selected.
                    </p>
                  ) : null}
                </div>
              </div>
            </section>

            <section>
              <h3 className="text-[15px] font-semibold text-[#aebed5]">
                Transfer to: {" "}
                <span className="text-[#ff404d]">
                  {targetLabel || "Select destination"}
                </span>
              </h3>

              <label className="mt-4 flex h-11 items-center overflow-hidden rounded-[3px] border border-[#3a4454] bg-[#151a21]">
                <input
                  value={destinationQuery}
                  onChange={(event) =>
                    setDestinationQuery(event.target.value)
                  }
                  className="min-w-0 flex-1 bg-transparent px-4 text-[11px] text-white outline-none placeholder:text-[#667287]"
                  placeholder="Customer or Dealer name"
                />
                <span className="grid h-11 w-12 place-items-center bg-[#075ee8] text-white">
                  <Search className="h-4 w-4" />
                </span>
              </label>

              <div className="st-scrollbar mt-4 min-h-[340px] max-h-[340px] overflow-y-auto rounded-[3px] border border-[#303846] bg-[#10141a] p-3">
                <DestinationTree
                  nodes={filteredTree}
                  level={0}
                  expanded={expanded}
                  selectedKey={selectedKey}
                  onToggle={(key) => {
                    setExpanded((current) => {
                      const next = new Set(current);

                      if (next.has(key)) {
                        next.delete(key);
                      } else {
                        next.add(key);
                      }

                      return next;
                    });
                  }}
                  onSelect={(node) => {
                    if (!node.targetType || !node.targetId) {
                      return;
                    }

                    setSelectedKey(node.key);
                    setTargetType(node.targetType);
                    setTargetId(node.targetId);
                    setTargetLabel(node.label);
                    setError("");
                  }}
                />

                {filteredTree.length === 0 ? (
                  <p className="px-4 py-12 text-center text-[10px] text-[#71819c]">
                    No destination matches this search.
                  </p>
                ) : null}
              </div>

              <label className="mt-4 block text-[10px] font-semibold text-[#8f9db2]">
                Transfer notes
                <textarea
                  value={notes}
                  onChange={(event) =>
                    setNotes(event.target.value)
                  }
                  maxLength={1000}
                  rows={3}
                  className="mt-2 w-full resize-none rounded-[3px] border border-[#3a4454] bg-[#151a21] px-4 py-3 text-[10px] text-white outline-none placeholder:text-[#667287]"
                  placeholder="Sale reference, delivery note, or reason"
                />
              </label>

              <p className="mt-3 text-[9px] leading-5 text-[#71819c]">
                Installed, assigned, damaged, lost, repaired, or retired
                Devices cannot be moved. Backend authorization independently
                verifies both the selected Devices and destination account.
              </p>
            </section>
          </div>

          {error ? (
            <p className="mt-5 rounded-[3px] border border-red-900/70 bg-red-950/40 px-4 py-3 text-[10px] font-medium text-red-300">
              {error}
            </p>
          ) : null}

          <footer className="mt-6 flex justify-end gap-3 border-t border-[#303846] pt-5">
            <button
              type="button"
              onClick={onClose}
              disabled={submitting}
              className="h-10 rounded-[3px] border border-[#495365] px-6 text-[11px] font-semibold text-[#c7cfdb] hover:bg-white/5 disabled:opacity-50"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={
                submitting ||
                devices.length === 0 ||
                !targetId ||
                !targetType
              }
              className="flex h-10 items-center gap-2 rounded-[3px] bg-[#075ee8] px-7 text-[11px] font-semibold text-white hover:bg-[#0a67f4] disabled:bg-[#3a465a] disabled:text-[#7f8ba0]"
            >
              {submitting ? (
                <LoaderCircle className="h-4 w-4 animate-spin" />
              ) : null}
              Confirm
            </button>
          </footer>
        </form>
      </section>
    </div>
  );
}