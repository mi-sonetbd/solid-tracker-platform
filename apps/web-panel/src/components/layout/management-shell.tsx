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
  type ReactNode,
} from "react";
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
  const router = useRouter();
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
              title={user.scopeLabel}
              aria-expanded={profileOpen}
              aria-haspopup="menu"
              onClick={() =>
                setProfileOpen((value) => !value)
              }
              className={[
                "flex max-w-[255px] items-center gap-2 rounded-[4px] px-2 py-1.5 transition",
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
                className="absolute right-0 top-[calc(100%+8px)] w-[230px] overflow-hidden rounded-[6px] border border-[#dce4ef] bg-white text-[#405779] shadow-[0_14px_35px_rgba(31,61,108,0.2)]"
              >
                <div className="border-b border-[#e5eaf2] px-4 py-3">
                  <p className="truncate text-[12px] font-semibold">
                    {user.fullName}
                  </p>
                  <p className="mt-0.5 truncate text-[10px] font-normal text-[#7c8ba5]">
                    {user.scopeLabel}
                  </p>
                </div>

                <Link
                  href="/management/settings"
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

      <main className="min-h-screen pt-[var(--st-topbar-height)]">
        {children}
      </main>
    </div>
  );
}