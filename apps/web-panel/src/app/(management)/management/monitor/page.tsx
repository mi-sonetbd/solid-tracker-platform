import {
  ChevronDown,
  Layers3,
  Map,
  MapPinned,
  Search,
  SlidersHorizontal,
  Target,
} from "lucide-react";
import { AccountTree } from "@/components/management/account-tree";
import { ManagedDeviceList } from "@/components/management/managed-device-list";
import { ManagementRail } from "@/components/management/management-rail";
import { TrackingMapClient } from "@/components/map/tracking-map-client";

const mapTools = [
  Target,
  MapPinned,
  Layers3,
  SlidersHorizontal,
  Map,
];

export default function ManagementMonitorPage() {
  return (
    <div className="flex h-[calc(100vh-var(--st-topbar-height))] min-w-[1380px] overflow-hidden">
      <ManagementRail />
      <AccountTree compact />
      <ManagedDeviceList />

      <section className="relative min-w-0 flex-1 overflow-hidden">
        <TrackingMapClient />

        <div className="absolute left-3 top-3 z-[1000] flex items-center gap-2">
          <label className="flex h-8 w-[255px] items-center rounded-[3px] bg-white px-3 shadow-sm">
            <input
              className="min-w-0 flex-1 border-0 bg-transparent text-[11px] outline-none placeholder:text-[#8b9ab4]"
              placeholder="Please enter address"
            />
            <Search className="h-4 w-4 text-[#357cf4]" />
          </label>

          <button
            type="button"
            className="flex h-8 min-w-[92px] items-center justify-between rounded-[3px] bg-white px-3 text-[11px] text-[#52698e] shadow-sm"
          >
            Default
            <ChevronDown className="h-4 w-4" />
          </button>
        </div>

        <div className="absolute right-3 top-4 z-[1000] flex flex-col gap-2">
          {mapTools.map((Icon, index) => (
            <button
              key={index}
              type="button"
              className={[
                "grid h-8 w-8 place-items-center rounded-[3px] bg-white text-[#405779] shadow-sm",
                index === 2 ? "bg-[#357cf4] text-white" : "",
              ].join(" ")}
            >
              <Icon className="h-4 w-4" />
            </button>
          ))}
        </div>

        <select className="absolute bottom-14 left-4 z-[1000] h-8 rounded-[3px] border border-[#cfd8e7] bg-white px-3 text-[11px] text-[#52698e] shadow-sm">
          <option>8s</option>
          <option>10s</option>
          <option>20s</option>
        </select>
      </section>
    </div>
  );
}