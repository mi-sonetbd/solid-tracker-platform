"use client";

import {
  LoaderCircle,
  RefreshCw,
} from "lucide-react";
import { StatusRing } from "@/components/ui/status-ring";
import {
  activeDeviceAssignment,
  deviceDisplayName,
} from "@/lib/customer/customer-asset-types";
import { useCustomerAssets } from "@/lib/customer/use-customer-assets";

type CustomerReportWorkspaceProps = {
  canViewVehicles: boolean;
  canViewHistory: boolean;
};

function percentage(
  part: number,
  total: number,
) {
  if (total === 0) return 0;

  return Math.round((part / total) * 10_000) / 100;
}

export function CustomerReportWorkspace({
  canViewVehicles,
  canViewHistory,
}: CustomerReportWorkspaceProps) {
  const {
    vehicles,
    loading,
    error,
    refresh,
  } = useCustomerAssets(canViewVehicles);
  const activated = vehicles.filter((vehicle) =>
    Boolean(activeDeviceAssignment(vehicle)),
  ).length;
  const inactivated = vehicles.length - activated;

  return (
    <div className="min-h-[calc(100vh-var(--st-topbar-height))] bg-[#f1f4f8] p-2">
      <section className="rounded-[5px] bg-white">
        <div className="flex h-11 items-end gap-9 border-b border-[#e2e8f1] px-5">
          {[
            "Device Overview",
            "Motion Overview",
            "Alert Overview",
          ].map((tab, index) => (
            <button
              key={tab}
              type="button"
              className={[
                "h-11 border-b-2 px-1 text-[12px] font-medium",
                index === 0
                  ? "border-[#357cf4] text-[#357cf4]"
                  : "border-transparent text-[#52698e]",
              ].join(" ")}
            >
              {tab}
            </button>
          ))}
        </div>

        <div className="px-4 pb-4 pt-3">
          <button
            type="button"
            onClick={refresh}
            aria-label="Refresh report assets"
          >
            <RefreshCw
              className={[
                "h-4 w-4 text-[#357cf4]",
                loading ? "animate-spin" : "",
              ].join(" ")}
            />
          </button>

          <div className="mt-1 flex flex-wrap justify-between gap-2">
            <StatusRing
              label="Total"
              value={
                vehicles.length > 0 ? "100%" : "0%"
              }
              detail={`Total ${vehicles.length}`}
              percentage={vehicles.length > 0 ? 100 : 0}
              color="#7774ff"
            />
            <StatusRing
              label="Activated"
              value={`${percentage(
                activated,
                vehicles.length,
              ).toFixed(2)}%`}
              detail={`Activated ${activated}`}
              percentage={percentage(
                activated,
                vehicles.length,
              )}
              color="#4c82ff"
            />
            <StatusRing
              label="Inactivated"
              value={`${percentage(
                inactivated,
                vehicles.length,
              ).toFixed(2)}%`}
              detail={`Inactivated ${inactivated}`}
              percentage={percentage(
                inactivated,
                vehicles.length,
              )}
              color="#20d0a2"
            />
            <StatusRing
              label="Expired"
              value="0.00%"
              detail="Expired 0"
              percentage={0}
              color="#ff8a62"
            />
            <StatusRing
              label="Expiring soon"
              value="0.00%"
              detail="Expiring soon 0"
              percentage={0}
              color="#ff5575"
            />
          </div>
        </div>
      </section>

      <section className="mt-2 overflow-hidden rounded-[5px] bg-white p-3">
        <div className="overflow-x-auto">
          <table className="w-full min-w-[1120px] text-center text-[11px]">
            <thead className="bg-[#edf1f7] text-[#405779]">
              <tr>
                {[
                  "No.",
                  "Device Name",
                  "Address",
                  "Mileage",
                  "GPS Positioning",
                  "GSM",
                  "Speed (km/h)",
                  "State",
                  "Group",
                  "Position Time",
                ].map((heading) => (
                  <th
                    key={heading}
                    className="border border-[#e2e8f1] px-3 py-3 font-semibold"
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
                    colSpan={10}
                    className="h-40 border border-[#e2e8f1] text-[#71819c]"
                  >
                    <span className="inline-flex items-center gap-2">
                      <LoaderCircle className="h-4 w-4 animate-spin text-[#357cf4]" />
                      Loading scoped report assets
                    </span>
                  </td>
                </tr>
              ) : error ? (
                <tr>
                  <td
                    colSpan={10}
                    className="h-32 border border-[#e2e8f1] text-red-700"
                  >
                    {error}
                  </td>
                </tr>
              ) : vehicles.length === 0 ? (
                <tr>
                  <td
                    colSpan={10}
                    className="h-32 border border-[#e2e8f1] text-[#71819c]"
                  >
                    No Customer vehicle is available for
                    reporting.
                  </td>
                </tr>
              ) : (
                vehicles.map((vehicle, index) => {
                  const assignment =
                    activeDeviceAssignment(vehicle);

                  return (
                    <tr
                      key={vehicle.id}
                      className="text-[#4f6385]"
                    >
                      <td className="border border-[#e2e8f1] px-3 py-3">
                        {index + 1}
                      </td>
                      <td className="border border-[#e2e8f1] px-3 py-3">
                        {deviceDisplayName(vehicle)}
                      </td>
                      <td className="border border-[#e2e8f1] px-3 py-3 text-[#357cf4]">
                        No position data
                      </td>
                      <td className="border border-[#e2e8f1] px-3 py-3">
                        -
                      </td>
                      <td className="border border-[#e2e8f1] px-3 py-3">
                        -
                      </td>
                      <td className="border border-[#e2e8f1] px-3 py-3">
                        -
                      </td>
                      <td className="border border-[#e2e8f1] px-3 py-3">
                        -
                      </td>
                      <td className="border border-[#e2e8f1] px-3 py-3">
                        {assignment
                          ? "Tracking pending"
                          : "No tracker"}
                      </td>
                      <td className="border border-[#e2e8f1] px-3 py-3">
                        Default Group
                      </td>
                      <td className="border border-[#e2e8f1] px-3 py-3">
                        {canViewHistory
                          ? "-"
                          : "Permission unavailable"}
                      </td>
                    </tr>
                  );
                })
              )}
            </tbody>
          </table>
        </div>
      </section>
    </div>
  );
}