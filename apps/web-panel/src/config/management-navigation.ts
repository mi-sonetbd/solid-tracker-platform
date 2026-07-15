import {
  BarChart3,
  CarFront,
  Monitor,
  Search,
  Settings2,
  UserRoundCog,
  UsersRound,
  Video,
} from "lucide-react";

export const managementNavigation = [
  {
    label: "Monitor",
    href: "/management/monitor",
    icon: Monitor,
  },
  {
    label: "Report",
    href: "/management/report",
    icon: BarChart3,
  },
  {
    label: "Device",
    href: "/management/device",
    icon: Settings2,
  },
  {
    label: "Account",
    href: "/management/accounts",
    icon: UsersRound,
  },
  {
    label: "Video",
    href: "/management/video",
    icon: Video,
  },
  {
    label: "Fleet",
    href: "/management/fleet",
    icon: CarFront,
  },
] as const;

export const managementUtilityNavigation = [
  {
    label: "Search",
    href: "/management/device",
    icon: Search,
  },
  {
    label: "Profile",
    href: "/management/accounts",
    icon: UserRoundCog,
  },
] as const;