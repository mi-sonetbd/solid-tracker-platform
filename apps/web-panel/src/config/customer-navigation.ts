import type { LucideIcon } from "lucide-react";
import {
  BellRing,
  Boxes,
  Car,
  ChartNoAxesColumnIncreasing,
  CircleGauge,
  ClipboardClock,
  FileChartColumn,
  Gauge,
  History,
  LayoutDashboard,
  MapPinned,
  Monitor,
  Navigation,
  RadioTower,
  Route,
  Settings2,
  ShieldAlert,
  SquareMenu,
  UserRound,
  UsersRound,
  Video,
} from "lucide-react";

export type MainSection = "monitor" | "report" | "device" | "video" | "fleet";

export type NavigationItem = {
  label: string;
  href: string;
  icon: LucideIcon;
};

export const mainNavigation: readonly NavigationItem[] = [
  { label: "Monitor", href: "/monitor", icon: MapPinned },
  {
    label: "Report",
    href: "/report",
    icon: ChartNoAxesColumnIncreasing,
  },
  { label: "Device", href: "/device", icon: RadioTower },
  { label: "Video", href: "/video", icon: Video },
  { label: "Fleet", href: "/fleet", icon: Car },
];

export const sectionNavigation: Record<
  MainSection,
  readonly NavigationItem[]
> = {
  monitor: [
    { label: "Objects", href: "/monitor", icon: Car },
    { label: "Alerts", href: "/monitor/alerts", icon: BellRing },
    { label: "Tracks", href: "/monitor/tracks", icon: Navigation },
    { label: "Multi-track", href: "/monitor/multi-track", icon: Route },
  ],
  report: [
    { label: "Overview", href: "/report", icon: SquareMenu },
    { label: "My report", href: "/report/my-report", icon: FileChartColumn },
    {
      label: "Auto report",
      href: "/report/auto-report",
      icon: ClipboardClock,
    },
    { label: "Task center", href: "/report/task-center", icon: Settings2 },
  ],
  device: [
    { label: "Devices", href: "/device", icon: RadioTower },
    { label: "Groups", href: "/device/groups", icon: Boxes },
    { label: "Activation", href: "/device/activation", icon: ShieldAlert },
    { label: "Overview", href: "/report", icon: CircleGauge },
  ],
  video: [
    { label: "Monitor", href: "/video", icon: Monitor },
    { label: "History", href: "/video/history", icon: History },
    { label: "Devices", href: "/device", icon: RadioTower },
  ],
  fleet: [
    { label: "Dashboard", href: "/fleet", icon: LayoutDashboard },
    { label: "Driver", href: "/fleet/drivers", icon: UserRound },
    { label: "Vehicle", href: "/fleet/vehicles", icon: Car },
    { label: "RFID history", href: "/fleet/rfid", icon: History },
    { label: "Route plan", href: "/fleet/routes", icon: Route },
    { label: "Fleet setup", href: "/fleet/settings", icon: Gauge },
    { label: "Users", href: "/customers", icon: UsersRound },
  ],
};