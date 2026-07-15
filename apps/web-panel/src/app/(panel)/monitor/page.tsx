import {
  ChevronDown,
  CirclePlus,
  Eye,
  Filter,
  Heart,
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

export default function MonitorPage() {
  return (
    <div className="flex h-[calc(100vh-58px)] min-h-[640px] bg-white">
      <section className="w-[410px] shrink-0 border-r border-[#dfe6ef] bg-white p-3">
        <div className="flex h-full flex-col rounded-md bg-[#f8fafd]">
          <div className="border-b border-[#e4e9f1] bg-white p-3">
            <label className="flex h-9 items-center rounded-[3px] border border-[#cfd8e7] px-3">
              <input
                className="min-w-0 flex-1 border-0 bg-transparent text-[12px] outline-none placeholder:text-[#8b9ab4]"
                placeholder="Please enter the device name or IMEI"
              />
              <Search className="h-4 w-4 text-[#607392]" />
            </label>

            <button
              type="button"
              className="mt-3 flex h-7 items-center gap-1 rounded border border-[#367cf6] px-2 text-[12px] font-medium text-[#367cf6]"
            >
              <CirclePlus className="h-4 w-4" />
              Add group
            </button>

            <div className="mt-3 flex items-center justify-between text-[12px] text-[#637493]">
              <div className="flex items-center gap-3">
                <span className="rounded bg-[#edf2f9] px-2 py-1 font-semibold text-[#344b72]">
                  All 1
                </span>
                <span className="font-semibold text-[#36b56d]">â–² 1</span>
                <span className="font-semibold text-[#ff5a74]">â™¥ 0</span>
                <span className="font-semibold text-[#344b72]">â–¥ 0</span>
              </div>
              <div className="flex items-center gap-3">
                <Eye className="h-4 w-4" />
                <Filter className="h-4 w-4" />
                <ListFilter className="h-4 w-4" />
                <RefreshCw className="h-4 w-4 text-[#367cf6]" />
              </div>
            </div>
          </div>

          <div className="flex-1 p-3">
            <div className="rounded-md border border-[#e1e7f0] bg-white">
              <div className="flex h-10 items-center justify-between bg-[#edf1f7] px-3 text-[12px] font-medium text-[#536889]">
                <div className="flex items-center gap-2">
                  <ChevronDown className="h-4 w-4" />
                  <span>Default group(1)</span>
                </div>
                <div className="flex items-center gap-3">
                  <Eye className="h-3.5 w-3.5" />
                  <MoreVertical className="h-4 w-4" />
                </div>
              </div>

              <article className="px-4 py-3">
                <div className="flex items-start gap-3">
                  <div className="grid h-10 w-10 shrink-0 place-items-center rounded-full bg-[#ff3152] text-white">
                    <MapPinned className="h-5 w-5" fill="currentColor" />
                  </div>
                  <div className="min-w-0 flex-1">
                    <div className="flex items-center justify-between">
                      <h2 className="text-[13px] font-bold text-[#405779]">
                        36-5958
                      </h2>
                      <span className="text-[11px] text-[#637493]">1hr+</span>
                    </div>
                    <p className="mt-1 text-[11px] text-[#9aa8bd]">
                      2026-07-15 11:11:01
                    </p>
                    <div className="mt-3 flex items-center justify-end gap-4 text-[#8090aa]">
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
      </section>

      <section className="relative min-w-0 flex-1 overflow-hidden">
        <TrackingMapClient />

        <div className="absolute left-3 right-3 top-3 z-[1000] flex items-center gap-3">
          <label className="flex h-9 w-[250px] items-center rounded-[3px] bg-white px-3 shadow-sm">
            <input
              className="min-w-0 flex-1 border-0 bg-transparent text-[12px] outline-none placeholder:text-[#8b9ab4]"
              placeholder="Please enter address"
            />
            <Search className="h-4 w-4 text-[#367cf6]" />
          </label>

          <button
            type="button"
            className="flex h-9 min-w-[92px] items-center justify-between rounded-[3px] bg-white px-3 text-[12px] text-[#5c6f8e] shadow-sm"
          >
            Default
            <ChevronDown className="h-4 w-4" />
          </button>
        </div>

        <div className="absolute right-3 top-5 z-[1000] flex flex-col gap-2">
          {[Target, MapPinned, SlidersHorizontal, Map, ListFilter].map(
            (Icon, index) => (
              <button
                key={index}
                type="button"
                className={[
                  "grid h-8 w-8 place-items-center rounded-[3px] bg-white text-[#405779] shadow-sm",
                  index === 3 ? "bg-[#367cf6] text-white" : "",
                ].join(" ")}
              >
                <Icon className="h-4 w-4" />
              </button>
            ),
          )}
        </div>

        <select className="absolute bottom-16 left-5 z-[1000] h-8 rounded-[3px] border border-[#cfd8e7] bg-white px-3 text-[12px] text-[#5c6f8e] shadow-sm">
          <option>20s</option>
          <option>10s</option>
          <option>30s</option>
        </select>
      </section>
    </div>
  );
}