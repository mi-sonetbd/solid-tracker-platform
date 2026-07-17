"use client";

import {
  ArrowDownAZ,
  Check,
  Eye,
  EyeOff,
  Filter,
  Heart,
  Navigation,
  RefreshCw,

} from "lucide-react";
import {
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import { useRouter } from "next/navigation";

export type CustomerDevicePrimaryFilter =
  | "all"
  | "online"
  | "following"
  | "offline";

export type CustomerDeviceMotionFilter =
  | "all"
  | "moving"
  | "idling"
  | "static";

export type CustomerDeviceSortMode =
  | "name-asc"
  | "name-desc"
  | "newest"
  | "oldest";

type UnknownRecord =
  Record<string, unknown>;

type DeviceDescriptor = {
  online: boolean | null;
  following: boolean;
  hidden: boolean;
  motion:
    | "moving"
    | "idling"
    | "static"
    | "unknown";
  name: string;
  updatedAt: number;
};

type DevicePanelCounts = {
  all: number;
  online: number;
  following: number;
  offline: number;
  moving: number;
  idling: number;
  static: number;
};

type CustomerDevicePanelToolbarProps = {
  primaryFilter:
    CustomerDevicePrimaryFilter;
  onPrimaryFilterChange: (
    value: CustomerDevicePrimaryFilter,
  ) => void;
  motionFilter:
    CustomerDeviceMotionFilter;
  onMotionFilterChange: (
    value: CustomerDeviceMotionFilter,
  ) => void;
  sortMode: CustomerDeviceSortMode;
  onSortModeChange: (
    value: CustomerDeviceSortMode,
  ) => void;
  showHiddenDevices: boolean;
  onToggleHiddenDevices: () => void;
  counts: DevicePanelCounts;
  onRefresh: () => void;
  refreshVersion: number;
};

const CHILD_COLLECTION_KEYS = [
  "devices",
  "items",
  "children",
  "objects",
  "vehicles",
  "trackers",
  "rows",
] as const;

const NAME_KEYS = [
  "name",
  "deviceName",
  "vehicleName",
  "objectName",
  "trackerName",
  "imei",
  "identifier",
  "plateNumber",
  "registrationNumber",
] as const;

const STATUS_KEYS = [
  "status",
  "onlineStatus",
  "connectionStatus",
  "deviceStatus",
  "motionStatus",
  "state",
] as const;

const UPDATED_KEYS = [
  "updatedAt",
  "lastUpdate",
  "lastUpdatedAt",
  "lastSeen",
  "gpsTime",
  "serverTime",
  "timestamp",
] as const;

function isRecord(
  value: unknown,
): value is UnknownRecord {
  return (
    typeof value === "object" &&
    value !== null &&
    !Array.isArray(value)
  );
}

function readString(
  record: UnknownRecord,
  keys: readonly string[],
): string | null {
  for (const key of keys) {
    const value = record[key];

    if (
      typeof value === "string" &&
      value.trim().length > 0
    ) {
      return value.trim();
    }

    if (
      typeof value === "number" &&
      Number.isFinite(value)
    ) {
      return String(value);
    }
  }

  return null;
}

function readBoolean(
  record: UnknownRecord,
  keys: readonly string[],
): boolean | null {
  for (const key of keys) {
    const value = record[key];

    if (typeof value === "boolean") {
      return value;
    }

    if (value === 1 || value === "1") {
      return true;
    }

    if (value === 0 || value === "0") {
      return false;
    }
  }

  return null;
}

function readTimestamp(
  record: UnknownRecord,
): number {
  for (const key of UPDATED_KEYS) {
    const value = record[key];

    if (
      typeof value === "number" &&
      Number.isFinite(value)
    ) {
      return value;
    }

    if (typeof value === "string") {
      const parsed = Date.parse(value);

      if (Number.isFinite(parsed)) {
        return parsed;
      }
    }
  }

  return 0;
}

function findChildCollection(
  record: UnknownRecord,
): {
  key: string;
  items: readonly unknown[];
} | null {
  for (const key of CHILD_COLLECTION_KEYS) {
    const value = record[key];

    if (Array.isArray(value)) {
      return {
        key,
        items: value,
      };
    }
  }

  return null;
}

function describeDevice(
  value: unknown,
): DeviceDescriptor {
  if (!isRecord(value)) {
    return {
      online: null,
      following: false,
      hidden: false,
      motion: "unknown",
      name: String(value ?? ""),
      updatedAt: 0,
    };
  }

  const explicitOnline = readBoolean(
    value,
    [
      "online",
      "isOnline",
      "connected",
      "isConnected",
    ],
  );

  const statusText =
    readString(
      value,
      STATUS_KEYS,
    )?.toLowerCase() ?? "";

  let online = explicitOnline;

  if (online === null) {
    if (
      /(^|\b)(online|connected)(\b|$)/.test(
        statusText,
      )
    ) {
      online = true;
    }
    else if (
      /(^|\b)(offline|disconnected)(\b|$)/.test(
        statusText,
      )
    ) {
      online = false;
    }
  }

  const following =
    readBoolean(
      value,
      [
        "following",
        "isFollowing",
        "favorite",
        "isFavorite",
        "favourite",
        "isFavourite",
        "starred",
        "isStarred",
      ],
    ) ?? false;

  const hiddenValue = readBoolean(
    value,
    [
      "hidden",
      "isHidden",
      "invisible",
      "isInvisible",
    ],
  );

  const visibleValue = readBoolean(
    value,
    [
      "visible",
      "isVisible",
    ],
  );

  const hidden =
    hiddenValue ??
    (
      visibleValue === null
        ? false
        : !visibleValue
    );

  let motion:
    DeviceDescriptor["motion"] =
      "unknown";

  if (
    /(^|\b)(moving|driving|running)(\b|$)/.test(
      statusText,
    )
  ) {
    motion = "moving";
  }
  else if (
    /(^|\b)(idling|idle)(\b|$)/.test(
      statusText,
    )
  ) {
    motion = "idling";
  }
  else if (
    /(^|\b)(static|stopped|parking|parked)(\b|$)/.test(
      statusText,
    )
  ) {
    motion = "static";
  }

  return {
    online,
    following,
    hidden,
    motion,
    name:
      readString(
        value,
        NAME_KEYS,
      ) ?? "",
    updatedAt:
      readTimestamp(value),
  };
}

function flattenLeaves(
  items: readonly unknown[],
): unknown[] {
  const result: unknown[] = [];

  for (const item of items) {
    if (isRecord(item)) {
      const childCollection =
        findChildCollection(item);

      if (childCollection) {
        result.push(
          ...flattenLeaves(
            childCollection.items,
          ),
        );
        continue;
      }
    }

    result.push(item);
  }

  return result;
}

function matchesPrimaryFilter(
  descriptor: DeviceDescriptor,
  filter:
    CustomerDevicePrimaryFilter,
): boolean {
  switch (filter) {
    case "online":
      return descriptor.online === true;
    case "following":
      return descriptor.following;
    case "offline":
      return descriptor.online === false;
    default:
      return true;
  }
}

function matchesMotionFilter(
  descriptor: DeviceDescriptor,
  filter:
    CustomerDeviceMotionFilter,
): boolean {
  return (
    filter === "all" ||
    descriptor.motion === filter
  );
}

function sortLeafItems<T>(
  items: readonly T[],
  sortMode: CustomerDeviceSortMode,
): T[] {
  const result = [...items];

  result.sort((left, right) => {
    const leftDescriptor =
      describeDevice(left);

    const rightDescriptor =
      describeDevice(right);

    switch (sortMode) {
      case "name-desc":
        return rightDescriptor.name.localeCompare(
          leftDescriptor.name,
          undefined,
          {
            numeric: true,
            sensitivity: "base",
          },
        );
      case "newest":
        return (
          rightDescriptor.updatedAt -
          leftDescriptor.updatedAt
        );
      case "oldest":
        return (
          leftDescriptor.updatedAt -
          rightDescriptor.updatedAt
        );
      default:
        return leftDescriptor.name.localeCompare(
          rightDescriptor.name,
          undefined,
          {
            numeric: true,
            sensitivity: "base",
          },
        );
    }
  });

  return result;
}

function createDevicePanelView<T>(
  items: readonly T[],
  primaryFilter:
    CustomerDevicePrimaryFilter,
  motionFilter:
    CustomerDeviceMotionFilter,
  sortMode: CustomerDeviceSortMode,
  showHiddenDevices: boolean,
): T[] {
  const result: T[] = [];

  for (const item of items) {
    if (isRecord(item)) {
      const childCollection =
        findChildCollection(item);

      if (childCollection) {
        const children =
          createDevicePanelView(
            childCollection.items,
            primaryFilter,
            motionFilter,
            sortMode,
            showHiddenDevices,
          );

        if (children.length > 0) {
          result.push({
            ...item,
            [childCollection.key]:
              children,
          } as T);
        }

        continue;
      }
    }

    const descriptor =
      describeDevice(item);

    if (
      !showHiddenDevices &&
      descriptor.hidden
    ) {
      continue;
    }

    if (
      !matchesPrimaryFilter(
        descriptor,
        primaryFilter,
      ) ||
      !matchesMotionFilter(
        descriptor,
        motionFilter,
      )
    ) {
      continue;
    }

    result.push(item);
  }

  return sortLeafItems(
    result,
    sortMode,
  );
}

function buildCounts(
  items: readonly unknown[],
  showHiddenDevices: boolean,
): DevicePanelCounts {
  const leaves = flattenLeaves(items).filter(
    (item) => {
      const descriptor =
        describeDevice(item);

      return (
        showHiddenDevices ||
        !descriptor.hidden
      );
    },
  );

  const counts: DevicePanelCounts = {
    all: leaves.length,
    online: 0,
    following: 0,
    offline: 0,
    moving: 0,
    idling: 0,
    static: 0,
  };

  for (const item of leaves) {
    const descriptor =
      describeDevice(item);

    if (descriptor.online === true) {
      counts.online += 1;
    }

    if (descriptor.online === false) {
      counts.offline += 1;
    }

    if (descriptor.following) {
      counts.following += 1;
    }

    if (
      descriptor.motion === "moving"
    ) {
      counts.moving += 1;
    }

    if (
      descriptor.motion === "idling"
    ) {
      counts.idling += 1;
    }

    if (
      descriptor.motion === "static"
    ) {
      counts.static += 1;
    }
  }

  return counts;
}

export function useCustomerDevicePanel<T>(
  sourceItems: readonly T[],
) {
  const router = useRouter();

  const [
    primaryFilter,
    setPrimaryFilter,
  ] =
    useState<CustomerDevicePrimaryFilter>(
      "all",
    );

  const [
    motionFilter,
    setMotionFilter,
  ] =
    useState<CustomerDeviceMotionFilter>(
      "all",
    );

  const [
    sortMode,
    setSortMode,
  ] =
    useState<CustomerDeviceSortMode>(
      "name-asc",
    );

  const [
    showHiddenDevices,
    setShowHiddenDevices,
  ] = useState(false);

  const [
    refreshVersion,
    setRefreshVersion,
  ] = useState(0);

  const counts = useMemo(
    () =>
      buildCounts(
        sourceItems,
        showHiddenDevices,
      ),
    [
      sourceItems,
      showHiddenDevices,
    ],
  );

  const items = useMemo(
    () =>
      createDevicePanelView(
        sourceItems,
        primaryFilter,
        motionFilter,
        sortMode,
        showHiddenDevices,
      ),
    [
      sourceItems,
      primaryFilter,
      motionFilter,
      sortMode,
      showHiddenDevices,
    ],
  );

  const toolbarProps:
    CustomerDevicePanelToolbarProps = {
      primaryFilter,
      onPrimaryFilterChange:
        setPrimaryFilter,
      motionFilter,
      onMotionFilterChange:
        setMotionFilter,
      sortMode,
      onSortModeChange:
        setSortMode,
      showHiddenDevices,
      onToggleHiddenDevices: () => {
        setShowHiddenDevices(
          (current) => !current,
        );
      },
      counts,
      onRefresh: () => {
        setRefreshVersion(
          (current) => current + 1,
        );
        router.refresh();
      },
      refreshVersion,
    };

  return {
    items,
    toolbarProps,
  };
}

function OfflineNetworkCrossIcon({
  className = "h-4 w-4",
}: {
  className?: string;
}) {
  return (
    <svg
      viewBox="0 0 20 20"
      fill="none"
      className={className}
      aria-hidden="true"
    >
      <path
        d="M3.25 15.75V13.1M6.6 15.75V10.55M9.95 15.75V7.85M13.3 15.75V5.1"
        stroke="currentColor"
        strokeWidth="1.7"
        strokeLinecap="round"
      />
      <path
        d="M15.25 7.05L18.1 9.9M18.1 7.05L15.25 9.9"
        stroke="currentColor"
        strokeWidth="1.75"
        strokeLinecap="round"
      />
    </svg>
  );
}

function CountButton({
  active,
  label,
  count,
  icon,
  onClick,
}: {
  active: boolean;
  label: string;
  count: number;
  icon?: React.ReactNode;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-pressed={active}
      aria-label={`${label}: ${count}`}
      title={label}
      className={[
        "inline-flex h-7 shrink-0 items-center gap-1 rounded-md px-1.5 text-[13px] font-medium transition",
        "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-500/40",
        active
          ? "bg-slate-100 text-slate-700"
          : "bg-transparent text-slate-700 hover:bg-slate-50",
      ].join(" ")}
    >
      {icon}
      {label === "All" ? (
        <span>All</span>
      ) : null}
      <span>{count}</span>
    </button>
  );
}

function ToolButton({
  active = false,
  label,
  children,
  onClick,
  expanded,
}: {
  active?: boolean;
  label: string;
  children: React.ReactNode;
  onClick: () => void;
  expanded?: boolean;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-pressed={active}
      aria-expanded={expanded}
      aria-label={label}
      title={label}
      className={[
        "inline-flex h-8 w-8 shrink-0 items-center justify-center rounded-md transition",
        "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-500/40",
        active
          ? "bg-slate-100 text-blue-600"
          : "text-slate-500 hover:bg-slate-50 hover:text-slate-700",
      ].join(" ")}
    >
      {children}
    </button>
  );
}

export function CustomerDevicePanelToolbar({
  primaryFilter,
  onPrimaryFilterChange,
  motionFilter,
  onMotionFilterChange,
  sortMode,
  onSortModeChange,
  showHiddenDevices,
  onToggleHiddenDevices,
  counts,
  onRefresh,
  refreshVersion,
}: CustomerDevicePanelToolbarProps) {
  const rootRef =
    useRef<HTMLDivElement>(null);

  const [
    isFilterOpen,
    setIsFilterOpen,
  ] = useState(false);

  const [
    isSortOpen,
    setIsSortOpen,
  ] = useState(false);

  useEffect(() => {
    const handlePointerDown = (
      event: PointerEvent,
    ) => {
      const root = rootRef.current;

      if (
        root &&
        event.target instanceof Node &&
        !root.contains(event.target)
      ) {
        setIsFilterOpen(false);
        setIsSortOpen(false);
      }
    };

    const handleKeyDown = (
      event: KeyboardEvent,
    ) => {
      if (event.key === "Escape") {
        setIsFilterOpen(false);
        setIsSortOpen(false);
      }
    };

    document.addEventListener(
      "pointerdown",
      handlePointerDown,
    );

    document.addEventListener(
      "keydown",
      handleKeyDown,
    );

    return () => {
      document.removeEventListener(
        "pointerdown",
        handlePointerDown,
      );

      document.removeEventListener(
        "keydown",
        handleKeyDown,
      );
    };
  }, []);

  const motionOptions = [
    {
      value: "all" as const,
      label: "All",
      count: counts.all,
      ringClass:
        "border-slate-500 bg-slate-500",
    },
    {
      value: "moving" as const,
      label: "Moving",
      count: counts.moving,
      ringClass:
        "border-green-500 bg-green-500",
    },
    {
      value: "idling" as const,
      label: "Idling",
      count: counts.idling,
      ringClass:
        "border-amber-500 bg-amber-400",
    },
    {
      value: "static" as const,
      label: "Static",
      count: counts.static,
      ringClass:
        "border-rose-500 bg-rose-500",
    },
  ];

  const sortOptions = [
    {
      value: "name-asc" as const,
      label: "Name A-Z",
    },
    {
      value: "name-desc" as const,
      label: "Name Z-A",
    },
    {
      value: "newest" as const,
      label: "Last update newest",
    },
    {
      value: "oldest" as const,
      label: "Last update oldest",
    },
  ];

  return (
    <div
      ref={rootRef}
      className="relative flex min-w-0 items-center justify-between gap-1 py-2"
      data-customer-device-panel-toolbar="true"
    >
      <div className="flex min-w-0 items-center gap-0.5">
        <CountButton
          active={primaryFilter === "all"}
          label="All"
          count={counts.all}
          onClick={() => {
            onPrimaryFilterChange("all");
          }}
        />

        <CountButton
          active={
            primaryFilter === "online"
          }
          label="Online"
          count={counts.online}
          icon={
            <Navigation
              className="h-4 w-4 fill-green-500 text-green-500"
              aria-hidden="true"
            />
          }
          onClick={() => {
            onPrimaryFilterChange(
              "online",
            );
          }}
        />

        <CountButton
          active={
            primaryFilter ===
            "following"
          }
          label="Following"
          count={counts.following}
          icon={
            <Heart
              className="h-4 w-4 fill-rose-400 text-rose-400"
              aria-hidden="true"
            />
          }
          onClick={() => {
            onPrimaryFilterChange(
              "following",
            );
          }}
        />

        <CountButton
          active={
            primaryFilter === "offline"
          }
          label="Offline"
          count={counts.offline}
          icon={
            <OfflineNetworkCrossIcon
              className="h-4 w-4 text-slate-700"
            />
          }
          onClick={() => {
            onPrimaryFilterChange(
              "offline",
            );
          }}
        />
      </div>

      <div className="flex shrink-0 items-center gap-0.5">
        <ToolButton
          active={showHiddenDevices}
          label={
            showHiddenDevices
              ? "Hide invisible devices"
              : "Show invisible devices"
          }
          onClick={
            onToggleHiddenDevices
          }
        >
          {showHiddenDevices ? (
            <Eye
              className="h-[18px] w-[18px]"
              aria-hidden="true"
            />
          ) : (
            <EyeOff
              className="h-[18px] w-[18px]"
              aria-hidden="true"
            />
          )}
        </ToolButton>

        <ToolButton
          active={
            motionFilter !== "all"
          }
          label="Filter devices"
          expanded={isFilterOpen}
          onClick={() => {
            setIsFilterOpen(
              (current) => !current,
            );
            setIsSortOpen(false);
          }}
        >
          <Filter
            className="h-[19px] w-[19px]"
            aria-hidden="true"
          />
        </ToolButton>

        <ToolButton
          active={
            sortMode !== "name-asc"
          }
          label="Sort devices"
          expanded={isSortOpen}
          onClick={() => {
            setIsSortOpen(
              (current) => !current,
            );
            setIsFilterOpen(false);
          }}
        >
          <ArrowDownAZ
            className="h-[19px] w-[19px]"
            aria-hidden="true"
          />
        </ToolButton>

        <ToolButton
          label="Refresh devices"
          onClick={onRefresh}
        >
          <RefreshCw
            key={refreshVersion}
            className="h-[19px] w-[19px]"
            aria-hidden="true"
          />
        </ToolButton>
      </div>

      {isFilterOpen ? (
        <div
          role="menu"
          aria-label="Device movement filter"
          className="absolute right-14 top-10 z-50 w-[148px] rounded-md border border-slate-200 bg-white py-1.5 shadow-lg"
        >
          {motionOptions.map(
            (option) => (
              <button
                key={option.value}
                type="button"
                role="menuitemradio"
                aria-checked={
                  motionFilter ===
                  option.value
                }
                onClick={() => {
                  onMotionFilterChange(
                    option.value,
                  );
                  setIsFilterOpen(false);
                }}
                className="flex w-full items-center gap-3 px-3 py-2 text-left text-[14px] text-slate-700 hover:bg-slate-50 focus-visible:outline-none focus-visible:bg-slate-50"
              >
                <span
                  className={[
                    "h-[17px] w-[17px] rounded-full border-2 bg-white p-[2px]",
                    option.ringClass
                      .split(" ")[0],
                  ].join(" ")}
                >
                  <span
                    className={[
                      "block h-full w-full rounded-full",
                      option.ringClass
                        .split(" ")[1],
                    ].join(" ")}
                  />
                </span>

                <span className="flex-1">
                  {option.label} (
                  {option.count})
                </span>

                {motionFilter ===
                option.value ? (
                  <Check
                    className="h-4 w-4 text-blue-600"
                    aria-hidden="true"
                  />
                ) : null}
              </button>
            ),
          )}
        </div>
      ) : null}

      {isSortOpen ? (
        <div
          role="menu"
          aria-label="Device sorting"
          className="absolute right-8 top-10 z-50 w-[190px] rounded-md border border-slate-200 bg-white py-1.5 shadow-lg"
        >
          {sortOptions.map(
            (option) => (
              <button
                key={option.value}
                type="button"
                role="menuitemradio"
                aria-checked={
                  sortMode ===
                  option.value
                }
                onClick={() => {
                  onSortModeChange(
                    option.value,
                  );
                  setIsSortOpen(false);
                }}
                className="flex w-full items-center gap-3 px-3 py-2 text-left text-[14px] text-slate-700 hover:bg-slate-50 focus-visible:outline-none focus-visible:bg-slate-50"
              >
                <span className="flex-1">
                  {option.label}
                </span>

                {sortMode ===
                option.value ? (
                  <Check
                    className="h-4 w-4 text-blue-600"
                    aria-hidden="true"
                  />
                ) : null}
              </button>
            ),
          )}
        </div>
      ) : null}
    </div>
  );
}
