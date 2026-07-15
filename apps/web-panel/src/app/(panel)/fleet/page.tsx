import {
  BarChart3,
  Car,
  ChevronDown,
  Fuel,
  RefreshCw,
  TimerReset,
  UserRound,
} from "lucide-react";

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
    <article className="rounded-md bg-white p-5 shadow-sm">
      <div className="flex items-start justify-between">
        <p className="text-[13px] text-[#52698e]">{label}</p>
        <Icon className="h-5 w-5 text-[#367cf6]" />
      </div>
      <p className="mt-6 text-[30px] font-semibold text-[#405779]">{value}</p>
      <button
        type="button"
        className="mt-4 flex h-7 items-center gap-2 rounded bg-[#edf4ff] px-2 text-[12px] text-[#367cf6]"
      >
        This week
        <ChevronDown className="h-3.5 w-3.5" />
      </button>
    </article>
  );
}

export default function FleetPage() {
  return (
    <div className="min-h-[calc(100vh-58px)] bg-[#f1f4f8] p-3">
      <h1 className="mb-3 text-[16px] font-semibold text-[#344b72]">
        Dashboard
      </h1>

      <section className="grid gap-3 xl:grid-cols-[1.25fr_0.82fr_0.82fr_0.82fr]">
        <article className="relative overflow-hidden rounded-md bg-gradient-to-br from-[#367cf6] to-[#6da0f6] p-5 text-white shadow-sm">
          <div className="grid grid-cols-2 gap-8">
            <div>
              <p className="text-[14px]">Total Drivers</p>
              <p className="mt-7 flex items-center gap-3 text-[30px] font-semibold">
                <UserRound className="h-5 w-5" fill="currentColor" />
                0
              </p>
            </div>
            <div>
              <p className="text-[14px]">Total Vehicles</p>
              <p className="mt-7 flex items-center gap-3 text-[30px] font-semibold">
                <Car className="h-5 w-5" fill="currentColor" />
                0
              </p>
            </div>
          </div>

          <p className="absolute bottom-4 left-5 text-[12px] text-white/90">
            Updated to 2026-07-15
          </p>
          <div className="absolute -bottom-14 -right-8 h-44 w-72 rotate-[-7deg] rounded-[50%] bg-white/10" />
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

      <section className="mt-3 grid gap-3 xl:grid-cols-[0.92fr_1.83fr]">
        <article className="min-h-[405px] rounded-md bg-white p-5 shadow-sm">
          <div className="flex items-center gap-2">
            <h2 className="text-[15px] font-semibold text-[#405779]">
              Reminder
            </h2>
            <RefreshCw className="h-3.5 w-3.5 text-[#8190a8]" />
          </div>

          <div className="mt-4 flex gap-5 text-[12px]">
            <button
              type="button"
              className="rounded-full bg-[#eaf2ff] px-3 py-1 text-[#367cf6]"
            >
              Driving license reminder
            </button>
            <button type="button" className="text-[#52698e]">
              Insurance reminder
            </button>
          </div>

          <div className="mt-9 flex flex-col items-center">
            <div className="h-[175px] w-[175px] rounded-full bg-[conic-gradient(#367cf6_0_33%,#6394ec_33%_66%,#cdd9f5_66%_100%)]" />
            <div className="mt-8 flex flex-wrap justify-center gap-5 text-[11px] text-[#637493]">
              {[
                ["#367cf6", "Normal"],
                ["#6394ec", "Expired"],
                ["#cdd9f5", "Expiring soon"],
              ].map(([color, label]) => (
                <span key={label} className="flex items-center gap-2">
                  <span
                    className="h-3 w-6 rounded-sm"
                    style={{ backgroundColor: color }}
                  />
                  {label}
                </span>
              ))}
            </div>
          </div>
        </article>

        <article className="min-h-[405px] rounded-md bg-white p-5 shadow-sm">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2">
              <h2 className="text-[15px] font-semibold text-[#405779]">
                Motion Statistics (H)
              </h2>
              <RefreshCw className="h-3.5 w-3.5 text-[#8190a8]" />
            </div>
            <button
              type="button"
              className="flex items-center gap-2 text-[12px] text-[#52698e]"
            >
              Last 7 days
              <ChevronDown className="h-4 w-4" />
            </button>
          </div>

          <div className="mt-4 flex gap-8 text-[12px]">
            <span className="rounded-full bg-[#eaf2ff] px-3 py-1 text-[#367cf6]">
              Exercise duration
            </span>
            <span>Idling duration</span>
            <span>Parked duration</span>
          </div>

          <div className="st-chart-grid relative mt-7 h-[285px] border-l border-b border-[#e2e8f1]">
            <div className="absolute -left-6 top-[-7px] text-[11px] text-[#8b9ab4]">1</div>
            <div className="absolute -left-8 top-[51px] text-[11px] text-[#8b9ab4]">0.8</div>
            <div className="absolute -left-8 top-[108px] text-[11px] text-[#8b9ab4]">0.6</div>
            <div className="absolute -left-8 top-[166px] text-[11px] text-[#8b9ab4]">0.4</div>
            <div className="absolute -left-8 top-[224px] text-[11px] text-[#8b9ab4]">0.2</div>
            <div className="absolute -left-6 bottom-[-5px] text-[11px] text-[#8b9ab4]">0</div>
          </div>
        </article>
      </section>

      <section className="mt-3 grid gap-3 xl:grid-cols-[0.92fr_1.83fr]">
        <article className="min-h-[300px] rounded-md bg-white p-5 shadow-sm">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2">
              <h2 className="text-[15px] font-semibold text-[#405779]">
                Alarm type ratio
              </h2>
              <RefreshCw className="h-3.5 w-3.5 text-[#8190a8]" />
            </div>
            <span className="flex items-center gap-2 text-[12px] text-[#52698e]">
              Last 7 days
              <ChevronDown className="h-4 w-4" />
            </span>
          </div>
        </article>

        <article className="min-h-[300px] rounded-md bg-white p-5 shadow-sm">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2">
              <h2 className="text-[15px] font-semibold text-[#405779]">
                Alarm statistics ranking
              </h2>
              <RefreshCw className="h-3.5 w-3.5 text-[#8190a8]" />
            </div>
            <span className="flex items-center gap-2 text-[12px] text-[#52698e]">
              Last 7 days
              <ChevronDown className="h-4 w-4" />
            </span>
          </div>

          <div className="mt-4 flex gap-6 text-[12px]">
            <span className="rounded-full bg-[#eaf2ff] px-3 py-1 text-[#367cf6]">
              Vehicle
            </span>
            <span>Alarm</span>
          </div>

          <div className="mt-5 grid grid-cols-3 border-b border-[#e2e8f1] pb-3 text-center text-[12px] text-[#8b9ab4]">
            <span>Ranking</span>
            <span>Number plate</span>
            <span>Alert Times</span>
          </div>
        </article>
      </section>
    </div>
  );
}