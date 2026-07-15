"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import {
  Bell,
  ChevronDown,
  CircleDollarSign,
} from "lucide-react";
import { SolidTrackerWordmark } from "@/components/brand/solid-tracker-wordmark";
import {
  mainNavigation,
  sectionNavigation,
  type MainSection,
} from "@/config/reference-navigation";

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

export function ReferenceShell({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  const pathname = usePathname();
  const activeSection = resolveSection(pathname);
  const railItems = sectionNavigation[activeSection];

  return (
    <div className="min-h-screen bg-[#f1f4f8] text-[#2b4065]">
      <header className="fixed inset-x-0 top-0 z-[1200] flex h-[var(--st-topbar-height)] items-stretch bg-[#357cf4] text-white shadow-[0_1px_3px_rgba(27,67,130,0.2)]">
        <div className="flex w-[200px] shrink-0 items-center justify-center rounded-br-[28px] bg-white px-4 shadow-[0_2px_7px_rgba(16,51,104,0.28)]">
          <SolidTrackerWordmark compact />
        </div>

        <nav
          aria-label="Platform sections"
          className="flex min-w-0 flex-1 items-stretch overflow-x-auto"
        >
          {mainNavigation.map((item) => {
            const active = isNavigationActive(pathname, item.href);
            const Icon = item.icon;

            return (
              <Link
                key={item.href}
                href={item.href}
                className={[
                  "flex min-w-[93px] items-center justify-center gap-1.5 border-r border-white/5 px-3 text-[13px] font-semibold transition",
                  active
                    ? "bg-[#2766d5] shadow-[inset_0_-3px_0_rgba(255,255,255,0.12)]"
                    : "hover:bg-white/10",
                ].join(" ")}
              >
                <Icon className="h-[17px] w-[17px]" strokeWidth={2.1} />
                <span>{item.label}</span>
              </Link>
            );
          })}
        </nav>

        <div className="ml-auto hidden items-center gap-4 px-4 text-[12px] font-semibold lg:flex">
          <Bell className="h-4 w-4 text-[#ff6879]" fill="currentColor" />
          <span className="flex items-center gap-1">
            <CircleDollarSign className="h-4 w-4" />
            <span>0</span>
          </span>
          <button
            type="button"
            className="flex items-center gap-1 text-white"
          >
            <span>admin</span>
            <ChevronDown className="h-3.5 w-3.5" />
          </button>
        </div>
      </header>

      <div className="flex min-h-screen pt-[var(--st-topbar-height)]">
        <aside className="fixed bottom-0 left-0 top-[var(--st-topbar-height)] z-[1100] w-[var(--st-rail-width)] overflow-y-auto border-r border-[#e0e7f0] bg-white">
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
                  <Icon className="h-[21px] w-[21px]" strokeWidth={1.85} />
                  <span className="max-w-[72px] leading-[14px]">
                    {item.label}
                  </span>
                </Link>
              );
            })}
          </nav>
        </aside>

        <main className="ml-[var(--st-rail-width)] min-w-0 flex-1">
          {children}
        </main>
      </div>
    </div>
  );
}