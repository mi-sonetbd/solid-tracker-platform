"use client";

import Link from "next/link";
import {
  ChevronDown,
  Grid3X3,
  List,
  LoaderCircle,
  MapPin,
  Pencil,
  Search,
  Send,
  UserRoundCog,
} from "lucide-react";
import {
  useMemo,
  useState,
  type FormEvent,
} from "react";
import { ActionButton } from "@/components/ui/action-button";
import {
  activeDeviceAssignment,
  formatAssetDate,
} from "@/lib/customer/customer-asset-types";
import { useCustomerAssets } from "@/lib/customer/use-customer-assets";

type CustomerDeviceWorkspaceProps = {
  canViewVehicles: boolean;
};

const leftActions = [
  "Import device",
  "Renew",
  "Sell/move",
  "Update user expiration",
];

const centerActions = [
  "Send Command",
  "Batch settings",
  "Bind device",
];

const rightActions = [
  "Disable",
  "Enable",
  "Batch operations",
  "Set group",
  "Allow activation",
];

export function CustomerDeviceWorkspace({
  canViewVehicles,
}: CustomerDeviceWorkspaceProps) {
  const { vehicles, loading, error } =
    useCustomerAssets(canViewVehicles);
  const [imeiInput, setImeiInput] = useState("");
  const [nameInput, setNameInput] = useState("");
  const [modelInput, setModelInput] = useState("");
  const [filters, setFilters] = useState({
    imei: "",
    name: "",
    model: "",
  });

  const installedAssets = useMemo(
    () =>
      vehicles
        .map((vehicle) => ({
          vehicle,
          assignment:
            activeDeviceAssignment(vehicle),
        }))
        .filter(
          (
            item,
          ): item is {
            vehicle: typeof item.vehicle;
            assignment: NonNullable<
              typeof item.assignment
            >;
          } => Boolean(item.assignment),
        ),
    [vehicles],
  );

  const modelOptions = useMemo(
    () =>
      Array.from(
        new Set(
          installedAssets.map(
            ({ assignment }) =>
              assignment.device.deviceModel.id,
          ),
        ),
      ).map((id) => {
        const model = installedAssets.find(
          ({ assignment }) =>
            assignment.device.deviceModel.id === id,
        )?.assignment.device.deviceModel;

        return model
          ? {
              id,
              label: `${model.manufacturer} ${model.modelName}`,
            }
          : null;
      }).filter(
        (
          item,
        ): item is {
          id: string;
          label: string;
        } => Boolean(item),
      ),
    [installedAssets],
  );

  const filteredAssets = useMemo(
    () =>
      installedAssets.filter(
        ({ vehicle, assignment }) => {
          const imei =
            assignment.device.imei?.toLowerCase() ?? "";
          const name = [
            vehicle.registrationNumber,
            vehicle.vehicleCode,
            assignment.device.deviceCode,
          ]
            .filter(Boolean)
            .join(" ")
            .toLowerCase();

          return (
            (!filters.imei ||
              imei.includes(filters.imei.toLowerCase())) &&
            (!filters.name ||
              name.includes(filters.name.toLowerCase())) &&
            (!filters.model ||
              assignment.device.deviceModel.id ===
                filters.model)
          );
        },
      ),
    [filters, installedAssets],
  );

  function search(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setFilters({
      imei: imeiInput.trim(),
      name: nameInput.trim(),
      model: modelInput,
    });
  }

  function reset() {
    setImeiInput("");
    setNameInput("");
    setModelInput("");
    setFilters({
      imei: "",
      name: "",
      model: "",
    });
  }

  return (
    <div className="min-h-[calc(100vh-var(--st-topbar-height))] bg-[#f4f6f9] p-2">
      <section className="min-h-[calc(100vh-var(--st-topbar-height)-16px)] rounded-[5px] bg-white px-3 pb-3 pt-2">
        <form
          onSubmit={search}
          className="grid gap-3 xl:grid-cols-[1.15fr_0.75fr_0.75fr_auto_auto_1fr]"
        >
          <input
            value={imeiInput}
            onChange={(event) =>
              setImeiInput(event.target.value)
            }
            className="h-8 rounded-[3px] border border-[#cfd8e7] px-3 text-[11px] outline-none focus:border-[#357cf4]"
            placeholder="IMEI(Press Enter for multiple lines)"
          />
          <input
            value={nameInput}
            onChange={(event) =>
              setNameInput(event.target.value)
            }
            className="h-8 rounded-[3px] border border-[#cfd8e7] px-3 text-[11px] outline-none focus:border-[#357cf4]"
            placeholder="Device name"
          />
          <select
            value={modelInput}
            onChange={(event) =>
              setModelInput(event.target.value)
            }
            className="h-8 rounded-[3px] border border-[#cfd8e7] bg-white px-3 text-[11px] text-[#647696]"
          >
            <option value="">All model</option>
            {modelOptions.map((model) => (
              <option key={model.id} value={model.id}>
                {model.label}
              </option>
            ))}
          </select>

          <ActionButton
            type="submit"
            className="h-8 px-4 text-[12px]"
          >
            <Search className="h-3.5 w-3.5" />
            Search
          </ActionButton>

          <ActionButton
            type="button"
            variant="outline"
            onClick={reset}
            className="h-8 px-4 text-[12px]"
          >
            Reset
          </ActionButton>

          <button
            type="button"
            className="ml-auto flex items-center gap-1 text-[11px] text-[#357cf4]"
          >
            Advanced Search
            <ChevronDown className="h-3.5 w-3.5" />
          </button>
        </form>

        <div className="mt-4 grid gap-3 border-y border-[#e1e7f0] py-3 xl:grid-cols-[1.05fr_1fr_1.08fr]">
          <div className="flex flex-wrap items-center justify-center gap-2 border-r border-[#e1e7f0] px-3">
            {leftActions.map((label) => (
              <ActionButton
                key={label}
                className="h-8 px-4 text-[12px]"
              >
                {label}
              </ActionButton>
            ))}
          </div>

          <div className="flex flex-wrap items-center justify-center gap-2 border-r border-[#e1e7f0] px-3">
            {centerActions.map((label, index) => (
              <ActionButton
                key={label}
                className="h-8 px-4 text-[12px]"
              >
                {label}
                {index < 2 ? (
                  <ChevronDown className="h-3.5 w-3.5" />
                ) : null}
              </ActionButton>
            ))}
          </div>

          <div className="flex flex-wrap items-center justify-center gap-2 px-3">
            {rightActions.map((label, index) => (
              <ActionButton
                key={label}
                className="h-8 px-4 text-[12px]"
              >
                {label}
                {index === 2 ? (
                  <ChevronDown className="h-3.5 w-3.5" />
                ) : null}
              </ActionButton>
            ))}
          </div>
        </div>

        <div className="mt-3 flex justify-end gap-2">
          <ActionButton
            variant="outline"
            className="h-8 px-4 text-[12px]"
          >
            Export
          </ActionButton>
          <ActionButton
            variant="outline"
            className="h-8 px-4 text-[12px]"
          >
            Export all
          </ActionButton>
          <button
            type="button"
            className="grid h-8 w-8 place-items-center rounded-[3px] text-[#405779] hover:bg-[#edf4ff]"
          >
            <Grid3X3 className="h-4 w-4" />
          </button>
        </div>

        <div className="mt-2 overflow-x-auto">
          <table className="w-full min-w-[1200px] text-center text-[10px]">
            <thead className="bg-[#edf1f7] text-[#405779]">
              <tr>
                <th className="w-12 px-3 py-3">
                  <input
                    type="checkbox"
                    aria-label="Select all devices"
                  />
                </th>
                {[
                  "No.",
                  "Device name",
                  "IMEI",
                  "Device Model",
                  "Activated time",
                  "Subscription Expiration",
                  "Expiration Date(U)",
                  "Actions",
                ].map((heading) => (
                  <th
                    key={heading}
                    className="px-3 py-3 font-semibold"
                  >
                    {heading}
                  </th>
                ))}
              </tr>
            </thead>

            <tbody>
              {loading ? (
                <tr>
                  <td
                    colSpan={9}
                    className="h-40 text-[#71819c]"
                  >
                    <span className="inline-flex items-center gap-2">
                      <LoaderCircle className="h-4 w-4 animate-spin text-[#357cf4]" />
                      Loading Customer devices
                    </span>
                  </td>
                </tr>
              ) : error ? (
                <tr>
                  <td
                    colSpan={9}
                    className="h-32 text-red-700"
                  >
                    {error}
                  </td>
                </tr>
              ) : filteredAssets.length === 0 ? (
                <tr>
                  <td
                    colSpan={9}
                    className="h-32 text-[#71819c]"
                  >
                    No installed device matches this Customer
                    scope.
                  </td>
                </tr>
              ) : (
                filteredAssets.map(
                  ({ vehicle, assignment }, index) => {
                    const device = assignment.device;
                    const model = device.deviceModel;

                    return (
                      <tr
                        key={assignment.id}
                        className="border-b border-[#e1e7f0] text-[#52698e]"
                      >
                        <td className="px-3 py-3">
                          <input
                            type="checkbox"
                            aria-label={`Select device ${device.deviceCode}`}
                          />
                        </td>
                        <td className="px-3 py-3">
                          {index + 1}
                        </td>
                        <td className="px-3 py-3">
                          {vehicle.registrationNumber ||
                            device.deviceCode}
                        </td>
                        <td className="px-3 py-3 text-[#357cf4]">
                          {device.imei || "-"}
                        </td>
                        <td className="px-3 py-3">
                          {model.modelName}
                        </td>
                        <td className="px-3 py-3">
                          {formatAssetDate(
                            assignment.startedAt,
                          )}
                        </td>
                        <td className="px-3 py-3">-</td>
                        <td className="px-3 py-3">-</td>
                        <td className="px-3 py-3">
                          <div className="flex items-center justify-center gap-4 text-[#357cf4]">
                            <Pencil className="h-3.5 w-3.5" />
                            <UserRoundCog className="h-3.5 w-3.5" />
                            <Link
                              href={`/monitor?vehicleId=${vehicle.id}`}
                              aria-label={`Locate ${device.deviceCode}`}
                            >
                              <MapPin className="h-3.5 w-3.5" />
                            </Link>
                            <List className="h-3.5 w-3.5" />
                            <Send className="h-3.5 w-3.5" />
                          </div>
                        </td>
                      </tr>
                    );
                  },
                )
              )}
            </tbody>
          </table>
        </div>
      </section>
    </div>
  );
}