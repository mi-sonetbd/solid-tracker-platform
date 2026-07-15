import {
  BellRing,
  CarFront,
  MapPinned,
  Route,
} from "lucide-react";

const items = [
  { label: "Objects", icon: CarFront, active: true },
  { label: "Alerts", icon: BellRing, active: false },
  { label: "Tracks", icon: MapPinned, active: false },
  { label: "Multi-track", icon: Route, active: false },
];

export function ManagementRail() {
  return (
    <aside className="flex w-[92px] shrink-0 flex-col items-center gap-3 border-r border-[#dfe6ef] bg-white px-2 py-3">
      {items.map((item) => {
        const Icon = item.icon;

        return (
          <button
            key={item.label}
            type="button"
            className={[
              "flex min-h-[86px] w-full flex-col items-center justify-center gap-2 rounded-[7px] text-[11px] font-semibold",
              item.active
                ? "bg-[#357cf4] text-white shadow-sm"
                : "text-[#405779] hover:bg-[#edf4ff]",
            ].join(" ")}
          >
            <Icon className="h-6 w-6" />
            <span>{item.label}</span>
          </button>
        );
      })}
    </aside>
  );
}