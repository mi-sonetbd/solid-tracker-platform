"use client";

import {
  BarChart3,
  Car,
  ChevronDown,
  Fuel,
  RefreshCw,
  TimerReset,
  UserRound,
} from "lucide-react";
import { useCustomerAssets } from "@/lib/customer/use-customer-assets";

function SummaryCard({
  label,
  value,
  icon: Icon,
}: {
  label: string;
  value: string;
  icon: typeof BarChart3;
}) {
  return (
    <article className="rounded-[5px] bg-white p-4 shadow-sm">
      <div className="flex items-start justify-between">
        <p className="text-[11px] text-[#52698e]">
          {label}
        </p>
        <Icon className="h-4 w-4 text-[#357cf4]" />
      </div>

      <p className="mt-5 text-[27px] font-semibold text-[#405779]">
        {value}
      </p>

      <button
        type="button"
        className="mt-3 flex h-7 items-center gap-2 rounded-[3px] bg-[#edf4ff] px-2 text-[11px] text-[#357cf4]"
      >
        This week
        <ChevronDown className="h-3.5 w-3.5" />
      </button>
    </article>
  );
}

const yAxisValues = [
  "1",
  "0.8",
  "0.6",
  "0.4",
  "0.2",
  "0",
];

export function CustomerFleetWorkspace({
  canViewVehicles,
}: {
  canViewVehicles: boolean;
}) {
  const {
    vehicles,
    loading,
    error,
    refresh,
  } = useCustomerAssets(canViewVehicles);

  return (
    <div className="min-h-[calc(100vh-var(--st-topbar-height))] bg-[#f1f4f8] p-2">
      <div className="mb-2 flex items-center gap-2">
        <h1 className="text-[14px] font-semibold text-[#344b72]">
          Dashboard
        </h1>
        <button
          type="button"
          onClick={refresh}
          aria-label="Refresh fleet dashboard"
        >
          <RefreshCw
            className={[
              "h-3.5 w-3.5 text-[#357cf4]",
              loading ? "animate-spin" : "",
            ].join(" ")}
          />
        </button>
        {error ? (
          <span className="text-[10px] text-red-700">
            {error}
          </span>
        ) : null}
      </div>

      <section className="grid gap-2 xl:grid-cols-[1.25fr_0.82fr_0.82fr_0.82fr]">
        <article className="relative min-h-[147px] overflow-hidden rounded-[5px] bg-gradient-to-br from-[#357cf4] to-[#6da0f6] p-4 text-white shadow-sm">
          <div className="grid grid-cols-2 gap-8">
            <div>
              <p className="text-[12px]">
                Total Drivers
              </p>
              <p className="mt-6 flex items-center gap-3 text-[27px] font-semibold">
                <UserRound
                  className="h-4 w-4"
                  fill="currentColor"
                />
                0
              </p>
            </div>

            <div>
              <p className="text-[12px]">
                Total Vehicles
              </p>
              <p className="mt-6 flex items-center gap-3 text-[27px] font-semibold">
                <Car
                  className="h-4 w-4"
                  fill="currentColor"
                />
                {vehicles.length}
              </p>
            </div>
          </div>

          <p className="absolute bottom-3 left-4 text-[10px] text-white/90">
            Updated from Customer asset scope
          </p>

          <div className="absolute -bottom-16 -right-6 h-44 w-72 rotate-[-7deg] rounded-[50%] bg-white/10" />
        </article>

        <SummaryCard
          label="Driven distance (km)"
          value="0"
          icon={BarChart3}
        />
        <SummaryCard
          label="Total driving time (H)"
          value="0"
          icon={TimerReset}
        />
        <SummaryCard
          label="Total fuel consumption (L)"
          value="0"
          icon={Fuel}
        />
      </section>

      <section className="mt-2 grid gap-2 xl:grid-cols-[0.92fr_1.83fr]">
        <article className="min-h-[350px] rounded-[5px] bg-white p-4 shadow-sm">
          <div className="flex items-center gap-2">
            <h2 className="text-[13px] font-semibold text-[#405779]">
              Reminder
            </h2>
            <RefreshCw className="h-3 w-3 text-[#8190a8]" />
          </div>

          <div className="mt-3 flex gap-5 text-[10px]">
            <button
              type="button"
              className="rounded-full bg-[#eaf2ff] px-3 py-1 text-[#357cf4]"
            >
              Driving license reminder
            </button>
            <button
              type="button"
              className="text-[#52698e]"
            >
              Insurance reminder
            </button>
          </div>

          <div className="mt-8 flex flex-col items-center">
            <div className="h-[150px] w-[150px] rounded-full bg-[conic-gradient(#357cf4_0_33%,#6394ec_33%_66%,#cdd9f5_66%_100%)]" />

            <div className="mt-7 flex flex-wrap justify-center gap-5 text-[10px] text-[#637493]">
              {[
                ["#357cf4", "Normal"],
                ["#6394ec", "Expired"],
                ["#cdd9f5", "Expiring soon"],
              ].map(([color, label]) => (
                <span
                  key={label}
                  className="flex items-center gap-2"
                >
                  <span
                    className="h-3 w-5 rounded-sm"
                    style={{
                      backgroundColor: color,
                    }}
                  />
                  {label}
                </span>
              ))}
            </div>
          </div>
        </article>

        <article className="min-h-[350px] overflow-hidden rounded-[5px] bg-white p-4 shadow-sm">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2">
              <h2 className="text-[13px] font-semibold text-[#405779]">
                Motion Statistics (H)
              </h2>
              <RefreshCw className="h-3 w-3 text-[#8190a8]" />
            </div>

            <button
              type="button"
              className="flex items-center gap-2 text-[11px] text-[#52698e]"
            >
              Last 7 days
              <ChevronDown className="h-3.5 w-3.5" />
            </button>
          </div>

          <div className="mt-3 flex gap-8 text-[10px]">
            <span className="rounded-full bg-[#eaf2ff] px-3 py-1 text-[#357cf4]">
              Exercise duration
            </span>
            <span>Idling duration</span>
            <span>Parked duration</span>
          </div>

          <div className="mt-6 grid h-[245px] min-w-0 grid-cols-[34px_minmax(0,1fr)]">
            <div className="flex h-full flex-col justify-between pb-[1px] pr-2 text-right text-[9px] leading-none text-[#8b9ab4]">
              {yAxisValues.map((value) => (
                <span key={value}>{value}</span>
              ))}
            </div>

            <div className="st-chart-grid min-w-0 border-b border-l border-[#e2e8f1]" />
          </div>
        </article>
      </section>

      <section className="mt-2 grid gap-2 xl:grid-cols-[0.92fr_1.83fr]">
        <article className="min-h-[260px] rounded-[5px] bg-white p-4 shadow-sm">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2">
              <h2 className="text-[13px] font-semibold text-[#405779]">
                Alarm type ratio
              </h2>
              <RefreshCw className="h-3 w-3 text-[#8190a8]" />
            </div>

            <span className="flex items-center gap-2 text-[10px] text-[#52698e]">
              Last 7 days
              <ChevronDown className="h-3.5 w-3.5" />
            </span>
          </div>
        </article>

        <article className="min-h-[260px] rounded-[5px] bg-white p-4 shadow-sm">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2">
              <h2 className="text-[13px] font-semibold text-[#405779]">
                Alarm statistics ranking
              </h2>
              <RefreshCw className="h-3 w-3 text-[#8190a8]" />
            </div>

            <span className="flex items-center gap-2 text-[10px] text-[#52698e]">
              Last 7 days
              <ChevronDown className="h-3.5 w-3.5" />
            </span>
          </div>

          <div className="mt-3 flex gap-6 text-[10px]">
            <span className="rounded-full bg-[#eaf2ff] px-3 py-1 text-[#357cf4]">
              Vehicle
            </span>
            <span>Alarm</span>
          </div>

          <div className="mt-4 grid grid-cols-3 border-b border-[#e2e8f1] pb-3 text-center text-[10px] text-[#8b9ab4]">
            <span>Ranking</span>
            <span>Number plate</span>
            <span>Alert Times</span>
          </div>
        </article>
      </section>
    </div>
  );
}