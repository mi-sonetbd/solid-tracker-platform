export type PanelRole =
  | "SUPER_ADMIN"
  | "ADMIN"
  | "DEALER_MANAGER"
  | "DEALER"
  | "CUSTOMER";

export type NavigationItem = {
  label: string;
  href: string;
  shortLabel: string;
  roles: readonly PanelRole[];
};

const allOperationalRoles: readonly PanelRole[] = [
  "SUPER_ADMIN",
  "ADMIN",
  "DEALER_MANAGER",
  "DEALER",
];

const allRoles: readonly PanelRole[] = [...allOperationalRoles, "CUSTOMER"];

export const panelNavigation: readonly NavigationItem[] = [
  {
    label: "Dashboard",
    href: "/dashboard",
    shortLabel: "DB",
    roles: allRoles,
  },
  {
    label: "Live Tracking",
    href: "/live-tracking",
    shortLabel: "LT",
    roles: allRoles,
  },
  {
    label: "Vehicles",
    href: "/vehicles",
    shortLabel: "VH",
    roles: allRoles,
  },
  {
    label: "Customers",
    href: "/customers",
    shortLabel: "CU",
    roles: allOperationalRoles,
  },
  {
    label: "Dealers",
    href: "/dealers",
    shortLabel: "DL",
    roles: ["SUPER_ADMIN", "ADMIN", "DEALER_MANAGER"],
  },
  {
    label: "Billing",
    href: "/billing",
    shortLabel: "BL",
    roles: allRoles,
  },
  {
    label: "Reports",
    href: "/reports",
    shortLabel: "RP",
    roles: allRoles,
  },
  {
    label: "Settings",
    href: "/settings",
    shortLabel: "ST",
    roles: allRoles,
  },
];