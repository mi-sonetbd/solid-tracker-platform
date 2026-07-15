import {
  ArrowUp,
  CarFront,
  ChevronDown,
  CirclePlus,
  Eye,
  Filter,
  Heart,
  ListFilter,
  MapPin,
  MoreVertical,
  Pencil,
  RefreshCw,
  Search,
  Signal,
} from "lucide-react";

const devices = [
  {
    name: "AT1-99300",
    time: "2026-07-08 21:45:45",
    state: "6day+",
  },
  {
    name: "VG03-35222",
    time: "2026-07-08 21:42:31",
    state: "6day+",
  },
  {
    name: "VG03-92014 - Damage",
    time: "2026-07-08 19:02:37",
    state: "6day+",
  },
  {
    name: "22 gari churi",
    time: "2026-07-08 18:34:09",
    state: "Inactive",
  },
];

export function ManagedDeviceList() {
  return (
    <section className="flex w-[455px] shrink-0 flex-col border-r border-[#dfe6ef] bg-[#f8fafc]">
      <div className="border-b border-[#e2e8f1] bg-white p-3">
        <h2 className="text-[13px] font-semibold text-[#405779]">
          Khaza Faisal Haque (Stock 10 / Total 7276)
        </h2>

        <label className="mt-3 flex h-8 items-center rounded-[3px] border border-[#cfd8e7] px-3">
          <input
            className="min-w-0 flex-1 border-0 bg-transparent text-[11px] outline-none placeholder:text-[#8b9ab4]"
            placeholder="Please enter the device name or IMEI"
          />
          <Search className="h-4 w-4 text-[#607392]" />
        </label>

        <button
          type="button"
          className="mt-3 flex h-7 items-center gap-1 rounded-[3px] border border-[#357cf4] px-2 text-[11px] text-[#357cf4]"
        >
          <CirclePlus className="h-4 w-4" />
          Add group
        </button>

        <div className="mt-3 flex items-center justify-between text-[11px]">
          <div className="flex items-center gap-3">
            <span className="rounded bg-[#edf2f8] px-2 py-1 font-semibold">
              All 10
            </span>
            <span className="flex items-center gap-0.5 text-[#30b56a]">
              <ArrowUp className="h-3 w-3" />0
            </span>
            <span className="flex items-center gap-0.5 text-[#ff5575]">
              <Heart className="h-3 w-3" fill="currentColor" />6
            </span>
            <span className="flex items-center gap-0.5 text-[#52698e]">
              <Signal className="h-3 w-3" />4
            </span>
          </div>

          <div className="flex items-center gap-3 text-[#607392]">
            <Eye className="h-3.5 w-3.5" />
            <Filter className="h-3.5 w-3.5" />
            <ListFilter className="h-3.5 w-3.5" />
            <RefreshCw className="h-3.5 w-3.5 text-[#357cf4]" />
          </div>
        </div>
      </div>

      <div className="flex h-10 items-center justify-between border-b border-[#e2e8f1] bg-[#edf2f8] px-4 text-[11px] font-semibold">
        <span className="flex items-center gap-2">
          <ChevronDown className="h-3.5 w-3.5" />
          Default group (10)
        </span>
        <span className="flex items-center gap-3">
          <Eye className="h-3.5 w-3.5" />
          <MoreVertical className="h-4 w-4" />
        </span>
      </div>

      <div className="st-scrollbar flex-1 overflow-y-auto">
        {devices.map((device) => (
          <article
            key={device.name}
            className="border-b border-[#e2e8f1] bg-white px-4 py-4"
          >
            <div className="flex items-start gap-3">
              <div className="grid h-10 w-10 shrink-0 place-items-center rounded-full bg-[#dfe9fb] text-[#357cf4]">
                <CarFront className="h-5 w-5" />
              </div>

              <div className="min-w-0 flex-1">
                <div className="flex items-center justify-between">
                  <h3 className="truncate text-[13px] font-semibold text-[#405779]">
                    {device.name}
                  </h3>
                  <span className="text-[10px] text-[#637493]">
                    {device.state}
                  </span>
                </div>

                <p className="mt-1 text-[10px] text-[#8b9ab4]">
                  {device.time}
                </p>

                <div className="mt-3 flex items-center justify-end gap-4 text-[#71819c]">
                  <Heart className="h-3.5 w-3.5" fill="#c8d0dd" />
                  <Pencil className="h-3.5 w-3.5" />
                  <MapPin className="h-3.5 w-3.5" />
                  <Eye className="h-3.5 w-3.5" />
                </div>
              </div>

              <MoreVertical className="h-4 w-4 text-[#607392]" />
            </div>
          </article>
        ))}
      </div>
    </section>
  );
}