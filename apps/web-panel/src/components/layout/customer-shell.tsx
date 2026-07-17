"use client";

import Link from "next/link";
import {
  usePathname,
  useRouter,
} from "next/navigation";
import {
  Bell,
  ChevronDown,
  CircleDollarSign,
  LoaderCircle,
  LogOut,
  Settings,
  UserRound,
} from "lucide-react";
import {
  useEffect,
  useRef,
  useState,
} from "react";
import { SolidTrackerWordmark } from "@/components/brand/solid-tracker-wordmark";
import {
  mainNavigation,
  sectionNavigation,
  type MainSection,
} from "@/config/customer-navigation";

function resolveSection(pathname: string): MainSection {
  if (pathname.startsWith("/report")) return "report";
  if (pathname.startsWith("/device")) return "device";
  if (pathname.startsWith("/video")) return "video";
  if (pathname.startsWith("/fleet")) return "fleet";
  return "monitor";
}

function isNavigationActive(pathname: string, href: string) {
  if (pathname === href) return true;
  return href !== "/" && pathname.startsWith(`${href}/`);
}

export function CustomerShell({
  children,
  user,
}: Readonly<{
  children: React.ReactNode;
  user: {
    fullName: string;
    workspaceLabel: string;
  };
}>) {
  const pathname = usePathname();
  const router = useRouter();
  const isMonitorRoute =
    pathname.startsWith("/monitor") ||
    pathname.startsWith("/alerts") ||
    pathname.startsWith("/tracks");

  const activeSection = isMonitorRoute
    ? "monitor"
    : resolveSection(pathname);
  const railItems = sectionNavigation[activeSection];
  const showSectionRail = activeSection !== "monitor";
  const menuRef = useRef<HTMLDivElement>(null);
  const [profileOpen, setProfileOpen] = useState(false);
  const [signingOut, setSigningOut] = useState(false);

  useEffect(() => {
    function closeOnOutsideClick(event: PointerEvent) {
      if (
        menuRef.current &&
        event.target instanceof Node &&
        !menuRef.current.contains(event.target)
      ) {
        setProfileOpen(false);
      }
    }

    function closeOnEscape(event: KeyboardEvent) {
      if (event.key === "Escape") {
        setProfileOpen(false);
      }
    }

    document.addEventListener("pointerdown", closeOnOutsideClick);
    document.addEventListener("keydown", closeOnEscape);

    return () => {
      document.removeEventListener(
        "pointerdown",
        closeOnOutsideClick,
      );
      document.removeEventListener("keydown", closeOnEscape);
    };
  }, []);

  async function signOut() {
    setSigningOut(true);
    setProfileOpen(false);

    try {
      await fetch("/api/auth/logout", {
        method: "POST",
      });
    } finally {
      router.replace("/login");
      router.refresh();
    }
  }

  return (
    <div className="min-h-screen bg-[#f1f4f8] text-[#2b4065]">
      <header className="fixed inset-x-0 top-0 z-[1200] flex h-[var(--st-topbar-height)] items-stretch bg-[#357cf4] text-white shadow-[0_1px_3px_rgba(27,67,130,0.2)]">
        <div className="flex w-[200px] shrink-0 items-center justify-center rounded-br-[28px] bg-white px-4 shadow-[0_2px_7px_rgba(16,51,104,0.28)]">
          <SolidTrackerWordmark compact />
        </div>

        <nav
          aria-label="Customer sections"
          className="flex min-w-0 flex-1 items-stretch overflow-x-auto"
        >
          {mainNavigation.map((item) => {
            const active =
              item.href === "/monitor"
                ? isMonitorRoute
                : isNavigationActive(pathname, item.href);
            const Icon = item.icon;

            return (
              <Link
                key={item.href}
                href={item.href}
                className={[
                  "flex h-full min-w-[93px] self-stretch items-center justify-center gap-1.5 border-r border-white/5 px-3 text-[13px] font-semibold transition",
                  active
                    ? "bg-[#2867dd] shadow-none"
                    : "hover:bg-white/10",
                  active && item.href === "/monitor"
                    ? "-ml-[18px] pl-[30px]"
                    : "",
                ].join(" ")}
              >
                <Icon
                  className="h-[17px] w-[17px]"
                  strokeWidth={2.1}
                />
                <span>{item.label}</span>
              </Link>
            );
          })}
        </nav>

        <div className="ml-auto hidden items-center gap-4 px-4 text-[12px] font-semibold lg:flex">
          <Bell
            className="h-4 w-4 text-[#ff6879]"
            fill="currentColor"
          />

          <span className="flex items-center gap-1">
            <CircleDollarSign className="h-4 w-4" />
            <span>0</span>
          </span>

          <div ref={menuRef} className="relative">
            <button
              type="button"
              aria-expanded={profileOpen}
              aria-haspopup="menu"
              title={user.workspaceLabel}
              onClick={() =>
                setProfileOpen((value) => !value)
              }
              className={[
                "flex max-w-[245px] items-center gap-2 rounded-[4px] px-2 py-1.5 transition",
                profileOpen
                  ? "bg-white/15"
                  : "hover:bg-white/10",
              ].join(" ")}
            >
              <span className="grid h-7 w-7 shrink-0 place-items-center rounded-full bg-white/15">
                <UserRound className="h-4 w-4" />
              </span>

              <span className="min-w-0 text-left">
                <span className="block truncate">
                  {user.fullName}
                </span>
                <span className="block truncate text-[9px] font-normal text-white/75">
                  {user.workspaceLabel}
                </span>
              </span>

              <ChevronDown
                className={[
                  "h-3.5 w-3.5 shrink-0 transition-transform",
                  profileOpen ? "rotate-180" : "",
                ].join(" ")}
              />
            </button>

            {profileOpen ? (
              <div
                role="menu"
                className="absolute right-0 top-[calc(100%+8px)] w-[220px] overflow-hidden rounded-[6px] border border-[#dce4ef] bg-white text-[#405779] shadow-[0_14px_35px_rgba(31,61,108,0.2)]"
              >
                <div className="border-b border-[#e5eaf2] px-4 py-3">
                  <p className="truncate text-[12px] font-semibold">
                    {user.fullName}
                  </p>
                  <p className="mt-0.5 truncate text-[10px] font-normal text-[#7c8ba5]">
                    Customer workspace
                  </p>
                </div>

                <Link
                  href="/settings"
                  role="menuitem"
                  onClick={() => setProfileOpen(false)}
                  className="flex h-10 items-center gap-3 px-4 text-[12px] font-medium transition hover:bg-[#edf4ff] hover:text-[#357cf4]"
                >
                  <Settings className="h-4 w-4" />
                  Settings
                </Link>

                <button
                  type="button"
                  role="menuitem"
                  disabled={signingOut}
                  onClick={signOut}
                  className="flex h-10 w-full items-center gap-3 border-t border-[#e5eaf2] px-4 text-left text-[12px] font-medium text-[#d6485f] transition hover:bg-red-50 disabled:cursor-not-allowed disabled:opacity-60"
                >
                  {signingOut ? (
                    <LoaderCircle className="h-4 w-4 animate-spin" />
                  ) : (
                    <LogOut className="h-4 w-4" />
                  )}
                  {signingOut ? "Signing out" : "Sign out"}
                </button>
              </div>
            ) : null}
          </div>
        </div>
      </header>

      <div className="flex min-h-screen pt-[var(--st-topbar-height)]">
        <aside className="fixed bottom-0 left-0 top-[var(--st-topbar-height)] z-[1100] w-[var(--st-rail-width)] overflow-y-auto border-r border-[#e0e7f0] bg-white" style={{ display: showSectionRail ? undefined : "none" }}>
          <nav
            aria-label={`${activeSection} navigation`}
            className="flex min-h-full flex-col items-center gap-2 px-[6px] py-2"
          >
            {railItems.map((item) => {
              const active = isNavigationActive(pathname, item.href);
              const Icon = item.icon;

              return (
                <Link
                  key={item.href}
                  href={item.href}
                  className={[
                    "flex min-h-[72px] w-full flex-col items-center justify-center gap-1.5 rounded-[7px] px-1 text-center text-[11px] font-semibold transition",
                    active
                      ? "bg-[#357cf4] text-white shadow-sm"
                      : "text-[#30486d] hover:bg-[#edf4ff] hover:text-[#2d70ed]",
                  ].join(" ")}
                >
                  <Icon
                    className="h-[21px] w-[21px]"
                    strokeWidth={1.85}
                  />
                  <span className="max-w-[72px] leading-[14px]">
                    {item.label}
                  </span>
                </Link>
              );
            })}
          </nav>
        </aside>

        <main className="ml-[var(--st-rail-width)] min-w-0 flex-1" style={{ marginLeft: showSectionRail ? undefined : 0, paddingLeft: showSectionRail ? undefined : 0 }}>
          {children}
        </main>
      </div>
    </div>
  );
}