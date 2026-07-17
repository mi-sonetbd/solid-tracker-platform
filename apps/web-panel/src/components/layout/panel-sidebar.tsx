import Link from "next/link";
import { panelNavigation } from "@/config/navigation";

export function PanelSidebar() {
  return (
    <aside className="hidden min-h-screen w-72 shrink-0 border-r border-slate-200 bg-slate-950 text-white lg:flex lg:flex-col">
      <div className="border-b border-white/10 px-7 py-7">
        <Link href="/dashboard" className="flex items-center gap-3">
          <span className="grid h-11 w-11 place-items-center rounded-2xl bg-teal-500 font-black text-slate-950">
            ST
          </span>
          <span>
            <span className="block text-lg font-bold tracking-tight">
              Solid Tracker
            </span>
            <span className="block text-xs text-slate-400">
              Operations Web Panel
            </span>
          </span>
        </Link>
      </div>

      <nav className="flex-1 space-y-1 px-4 py-6" aria-label="Main navigation">
        {panelNavigation.map((item) => (
          <Link
            key={item.href}
            href={item.href}
            className="flex items-center gap-3 rounded-xl px-3 py-3 text-sm font-medium text-slate-300 transition hover:bg-white/10 hover:text-white"
          >
            <span className="grid h-8 w-8 place-items-center rounded-lg bg-white/10 text-xs font-bold text-teal-300">
              {item.shortLabel}
            </span>
            {item.label}
          </Link>
        ))}
      </nav>

      <div className="border-t border-white/10 p-5">
        <div className="rounded-2xl bg-white/5 p-4">
          <p className="text-xs font-semibold uppercase tracking-[0.16em] text-teal-300">
            Backend
          </p>
          <p className="mt-2 text-sm font-semibold">API verified</p>
          <p className="mt-1 text-xs leading-5 text-slate-400">
            Authentication, tracking, billing, notifications, and mobile APIs
            passed their quality gates.
          </p>
        </div>
      </div>
    </aside>
  );
}