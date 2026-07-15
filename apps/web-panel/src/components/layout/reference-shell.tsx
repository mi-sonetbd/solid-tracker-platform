"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import {
  Bell,
  ChevronDown,
  CircleDollarSign,
  RadioTower,
} from "lucide-react";
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

function Brand() {
  return (
    <Link
      href="/monitor"
      className="flex h-[58px] min-w-[235px] items-center justify-center rounded-br-[30px] bg-white px-5 shadow-[0_2px_7px_rgba(16,51,104,0.28)]"
    >
      <span className="text-[27px] font-black italic tracking-[-1.5px] text-[#1394dc]">
        Solid
      </span>
      <span className="text-[27px] font-black italic tracking-[-1.5px] text-[#ff9f2f]">
        Tracker
      </span>
      <RadioTower className="ml-1 h-5 w-5 text-[#ff9f2f]" strokeWidth={2.3} />
    </Link>
  );
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
    <div className="min-h-screen bg-[#f1f4f8] text-[#263858]">
      <header className="fixed inset-x-0 top-0 z-[1200] flex h-[58px] items-stretch bg-[#367cf6] text-white shadow-sm">
        <Brand />

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
                  "flex min-w-[103px] items-center justify-center gap-2 px-4 text-[14px] font-semibold transition",
                  active
                    ? "bg-[#2464d8] shadow-[inset_0_-3px_0_rgba(255,255,255,0.17)]"
                    : "hover:bg-white/10",
                ].join(" ")}
              >
                <Icon className="h-[19px] w-[19px]" strokeWidth={2.2} />
                <span>{item.label}</span>
              </Link>
            );
          })}
        </nav>

        <div className="ml-auto hidden items-center gap-5 px-5 text-[13px] font-semibold lg:flex">
          <Bell className="h-4 w-4 text-[#ff6f7d]" fill="currentColor" />
          <span className="flex items-center gap-1">
            <CircleDollarSign className="h-4 w-4" />
            <span>0</span>
          </span>
          <button
            type="button"
            className="flex items-center gap-1.5 text-white"
          >
            <span>admin</span>
            <ChevronDown className="h-4 w-4" />
          </button>
        </div>
      </header>

      <div className="flex min-h-screen pt-[58px]">
        <aside className="fixed bottom-0 left-0 top-[58px] z-[1100] w-[100px] overflow-y-auto border-r border-[#e2e8f1] bg-white">
          <nav
            aria-label={`${activeSection} navigation`}
            className="flex min-h-full flex-col items-center gap-3 px-2 py-3"
          >
            {railItems.map((item) => {
              const active = isNavigationActive(pathname, item.href);
              const Icon = item.icon;

              return (
                <Link
                  key={item.href}
                  href={item.href}
                  className={[
                    "flex min-h-[78px] w-full flex-col items-center justify-center gap-2 rounded-lg px-1 text-center text-[12px] font-semibold transition",
                    active
                      ? "bg-[#367cf6] text-white shadow-sm"
                      : "text-[#344b72] hover:bg-[#edf4ff] hover:text-[#2d70ed]",
                  ].join(" ")}
                >
                  <Icon className="h-[23px] w-[23px]" strokeWidth={1.8} />
                  <span className="max-w-[82px] leading-[15px]">
                    {item.label}
                  </span>
                </Link>
              );
            })}
          </nav>
        </aside>

        <main className="ml-[100px] min-w-0 flex-1">{children}</main>
      </div>
    </div>
  );
}