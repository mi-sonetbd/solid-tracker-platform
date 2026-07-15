"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import {
  Bell,
  ChevronDown,
  CircleDollarSign,
} from "lucide-react";
import type { ReactNode } from "react";
import { SolidTrackerWordmark } from "@/components/brand/solid-tracker-wordmark";
import { managementNavigation } from "@/config/management-navigation";

type ManagementShellProps = {
  children: ReactNode;
  user: {
    fullName: string;
    workspaceLabel: string;
    scopeLabel: string;
  };
};

function activePath(pathname: string, href: string) {
  return pathname === href || pathname.startsWith(`${href}/`);
}

export function ManagementShell({
  children,
  user,
}: ManagementShellProps) {
  const pathname = usePathname();

  return (
    <div className="min-h-screen bg-[#eef2f7] text-[#2b4065]">
      <header className="fixed inset-x-0 top-0 z-[1200] flex h-[var(--st-topbar-height)] items-stretch bg-[#357cf4] text-white shadow-[0_1px_3px_rgba(27,67,130,0.2)]">
        <div className="flex w-[205px] shrink-0 items-center justify-center rounded-br-[28px] bg-white px-4 shadow-[0_2px_7px_rgba(16,51,104,0.28)]">
          <SolidTrackerWordmark compact />
        </div>

        <nav
          aria-label="Management sections"
          className="flex min-w-0 flex-1 items-stretch overflow-x-auto"
        >
          {managementNavigation.map((item) => {
            const Icon = item.icon;
            const active = activePath(pathname, item.href);

            return (
              <Link
                key={item.href}
                href={item.href}
                className={[
                  "flex min-w-[96px] items-center justify-center gap-1.5 border-r border-white/5 px-3 text-[13px] font-semibold transition",
                  active
                    ? "bg-[#2766d5] shadow-[inset_0_-3px_0_rgba(255,255,255,0.14)]"
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
            title={user.scopeLabel}
            className="flex max-w-[230px] items-center gap-1"
          >
            <span className="truncate">{user.fullName}</span>
            <span className="rounded-full bg-white/15 px-2 py-0.5 text-[10px]">
              {user.workspaceLabel}
            </span>
            <ChevronDown className="h-3.5 w-3.5" />
          </button>
        </div>
      </header>

      <main className="min-h-screen pt-[var(--st-topbar-height)]">
        {children}
      </main>
    </div>
  );
}