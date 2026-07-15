import {
  Car,
  ChevronDown,
  CirclePlus,
  Eye,
  Filter,
  Heart,
  Layers3,
  ListFilter,
  Map,
  MapPinned,
  MoreVertical,
  Pencil,
  RefreshCw,
  Search,
  SlidersHorizontal,
  Target,
} from "lucide-react";
import { TrackingMapClient } from "@/components/map/tracking-map-client";

const mapTools = [
  Target,
  MapPinned,
  SlidersHorizontal,
  Layers3,
  Map,
  ListFilter,
];

export default function MonitorPage() {
  return (
    <div className="flex h-[calc(100vh-var(--st-topbar-height))] min-h-[620px] bg-white">
      <section className="relative w-[350px] shrink-0 border-r border-[#dde5ef] bg-[#f6f8fb] p-2">
        <div className="flex h-full flex-col overflow-hidden rounded-[5px] bg-[#f7f9fc]">
          <div className="border-b border-[#e1e7f0] bg-white px-3 pb-2 pt-3">
            <label className="flex h-8 items-center rounded-[3px] border border-[#cfd8e7] px-3">
              <input
                className="min-w-0 flex-1 border-0 bg-transparent text-[12px] outline-none placeholder:text-[#8b9ab4]"
                placeholder="Please enter the device name or IMEI"
              />
              <Search className="h-4 w-4 text-[#607392]" />
            </label>

            <button
              type="button"
              className="mt-2 flex h-7 items-center gap-1 rounded-[3px] border border-[#357cf4] px-2 text-[12px] font-medium text-[#357cf4]"
            >
              <CirclePlus className="h-4 w-4" />
              Add group
            </button>

            <div className="mt-2 flex items-center justify-between text-[11px] text-[#637493]">
              <div className="flex items-center gap-2.5">
                <span className="rounded-[3px] bg-[#edf2f8] px-2 py-1 font-semibold text-[#344b72]">
                  All 1
                </span>
                <span className="font-semibold text-[#30b56a]">â–² 1</span>
                <span className="font-semibold text-[#ff5b75]">â™¥ 0</span>
                <span className="font-semibold text-[#344b72]">â–¥ 0</span>
              </div>
              <div className="flex items-center gap-2.5">
                <Eye className="h-3.5 w-3.5" />
                <Filter className="h-3.5 w-3.5" />
                <ListFilter className="h-3.5 w-3.5" />
                <RefreshCw className="h-3.5 w-3.5 text-[#357cf4]" />
              </div>
            </div>
          </div>

          <div className="flex-1 overflow-y-auto p-3">
            <div className="rounded-[4px] border border-[#dfe6ef] bg-white">
              <div className="flex h-9 items-center justify-between bg-[#edf1f7] px-3 text-[11px] font-medium text-[#536889]">
                <div className="flex items-center gap-2">
                  <ChevronDown className="h-3.5 w-3.5" />
                  <span>Default group(1)</span>
                </div>
                <div className="flex items-center gap-3">
                  <Eye className="h-3.5 w-3.5" />
                  <MoreVertical className="h-4 w-4" />
                </div>
              </div>

              <article className="px-3 py-3">
                <div className="flex items-start gap-3">
                  <div className="grid h-9 w-9 shrink-0 place-items-center rounded-full bg-[#ff3152] text-white">
                    <Car className="h-5 w-5" fill="currentColor" />
                  </div>

                  <div className="min-w-0 flex-1">
                    <div className="flex items-center justify-between">
                      <h2 className="text-[12px] font-bold text-[#405779]">
                        36-5958
                      </h2>
                      <span className="text-[10px] text-[#637493]">1hr+</span>
                    </div>
                    <p className="mt-1 text-[10px] text-[#9aa8bd]">
                      2026-07-15 11:11:01
                    </p>
                    <div className="mt-3 flex items-center justify-end gap-3.5 text-[#8090aa]">
                      <Heart className="h-3.5 w-3.5" fill="#c8d0dd" />
                      <Pencil className="h-3.5 w-3.5" />
                      <Target className="h-3.5 w-3.5" />
                      <Eye className="h-3.5 w-3.5" />
                    </div>
                  </div>

                  <MoreVertical className="h-4 w-4 text-[#4a5f80]" />
                </div>
              </article>
            </div>
          </div>
        </div>

        <button
          type="button"
          aria-label="Collapse object panel"
          className="absolute -right-[7px] top-1/2 z-[1001] grid h-36 w-[8px] -translate-y-1/2 place-items-center rounded-r bg-[#d9e3f2] text-[#6e80a0]"
        >
          â€¹
        </button>
      </section>

      <section className="relative min-w-0 flex-1 overflow-hidden">
        <TrackingMapClient />

        <div className="absolute left-3 top-3 z-[1000] flex items-center gap-2">
          <label className="flex h-8 w-[220px] items-center rounded-[3px] bg-white px-3 shadow-sm">
            <input
              className="min-w-0 flex-1 border-0 bg-transparent text-[12px] outline-none placeholder:text-[#8b9ab4]"
              placeholder="Please enter address"
            />
            <Search className="h-4 w-4 text-[#357cf4]" />
          </label>

          <button
            type="button"
            className="flex h-8 min-w-[84px] items-center justify-between rounded-[3px] bg-white px-3 text-[12px] text-[#5c6f8e] shadow-sm"
          >
            Default
            <ChevronDown className="h-4 w-4" />
          </button>
        </div>

        <div className="absolute right-2.5 top-4 z-[1000] flex flex-col gap-1.5">
          {mapTools.map((Icon, index) => (
            <button
              key={index}
              type="button"
              className={[
                "grid h-8 w-8 place-items-center rounded-[3px] bg-white text-[#405779] shadow-sm",
                index === 3 ? "bg-[#357cf4] text-white" : "",
              ].join(" ")}
            >
              <Icon className="h-4 w-4" />
            </button>
          ))}
        </div>

        <select className="absolute bottom-14 left-4 z-[1000] h-8 rounded-[3px] border border-[#cfd8e7] bg-white px-3 text-[12px] text-[#5c6f8e] shadow-sm">
          <option>20s</option>
          <option>10s</option>
          <option>30s</option>
        </select>
      </section>
    </div>
  );
}