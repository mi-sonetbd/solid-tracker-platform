import Link from "next/link";
import { StatCard } from "@/components/dashboard/stat-card";

const developmentModules = [
  {
    name: "Authentication",
    state: "Next",
    description: "Secure login, refresh tokens, logout, and session recovery.",
  },
  {
    name: "Role authorization",
    state: "Planned",
    description:
      "Super admin, admin, dealer manager, dealer, and customer access.",
  },
  {
    name: "Live tracking",
    state: "Planned",
    description: "Map, online state, telemetry, and vehicle selection.",
  },
  {
    name: "Operations",
    state: "Planned",
    description: "Vehicles, devices, customers, dealers, billing, and reports.",
  },
];

export default function DashboardPage() {
  return (
    <div className="space-y-7">
      <section className="overflow-hidden rounded-3xl bg-slate-950 p-7 text-white shadow-xl md:p-10">
        <div className="max-w-3xl">
          <p className="text-xs font-bold uppercase tracking-[0.2em] text-teal-300">
            Frontend foundation
          </p>
          <h1 className="mt-4 text-3xl font-black tracking-tight md:text-5xl">
            Solid Tracker Operations Panel
          </h1>
          <p className="mt-4 max-w-2xl text-sm leading-7 text-slate-300 md:text-base">
            One responsive web application for platform administration,
            dealers, customers, vehicles, billing, reports, and live GPS
            tracking.
          </p>
          <div className="mt-7 flex flex-wrap gap-3">
            <Link
              href="/live-tracking"
              className="rounded-xl bg-teal-400 px-5 py-3 text-sm font-bold text-slate-950 transition hover:bg-teal-300"
            >
              Open live tracking
            </Link>
            <Link
              href="/vehicles"
              className="rounded-xl border border-white/20 px-5 py-3 text-sm font-bold text-white transition hover:bg-white/10"
            >
              View vehicles
            </Link>
          </div>
        </div>
      </section>

      <section className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <StatCard
          label="Backend quality gates"
          value="Passed"
          detail="Lint, typecheck, tests, E2E, and production build."
        />
        <StatCard
          label="Database migrations"
          value="6"
          detail="PostgreSQL schema is fully up to date."
        />
        <StatCard
          label="Backend unit tests"
          value="18"
          detail="All current unit tests passed."
        />
        <StatCard
          label="Backend E2E tests"
          value="11"
          detail="All current end-to-end tests passed."
        />
      </section>

      <section className="grid gap-6 xl:grid-cols-[1.4fr_0.6fr]">
        <div className="rounded-3xl border border-slate-200 bg-white p-6 shadow-sm md:p-8">
          <div className="flex flex-wrap items-end justify-between gap-3">
            <div>
              <p className="text-xs font-bold uppercase tracking-[0.16em] text-teal-700">
                Implementation sequence
              </p>
              <h2 className="mt-2 text-2xl font-black tracking-tight text-slate-950">
                Web panel development modules
              </h2>
            </div>
            <span className="rounded-full bg-teal-50 px-3 py-1.5 text-xs font-semibold text-teal-700">
              Foundation active
            </span>
          </div>

          <div className="mt-6 divide-y divide-slate-100">
            {developmentModules.map((module) => (
              <article
                key={module.name}
                className="grid gap-3 py-5 sm:grid-cols-[1fr_auto] sm:items-center"
              >
                <div>
                  <h3 className="font-bold text-slate-950">{module.name}</h3>
                  <p className="mt-1 text-sm leading-6 text-slate-500">
                    {module.description}
                  </p>
                </div>
                <span className="w-fit rounded-full bg-slate-100 px-3 py-1.5 text-xs font-bold text-slate-600">
                  {module.state}
                </span>
              </article>
            ))}
          </div>
        </div>

        <aside className="rounded-3xl border border-slate-200 bg-white p-6 shadow-sm md:p-8">
          <p className="text-xs font-bold uppercase tracking-[0.16em] text-teal-700">
            Current stage
          </p>
          <h2 className="mt-3 text-2xl font-black tracking-tight text-slate-950">
            Frontend before Flutter
          </h2>
          <p className="mt-4 text-sm leading-7 text-slate-600">
            The web panel will validate backend contracts, roles, tracking
            workflows, and operational screens before the customer mobile
            application is started.
          </p>
          <div className="mt-6 rounded-2xl bg-slate-950 p-5 text-white">
            <p className="text-sm font-bold">Next implementation</p>
            <p className="mt-2 text-sm leading-6 text-slate-300">
              Web authentication and role-aware protected routing.
            </p>
          </div>
        </aside>
      </section>
    </div>
  );
}