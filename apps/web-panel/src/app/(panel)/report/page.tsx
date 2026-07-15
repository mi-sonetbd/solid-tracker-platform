import { RefreshCw } from "lucide-react";
import { StatusRing } from "@/components/ui/status-ring";

const reportRows = [
  {
    no: 1,
    device: "36-5958",
    address: "Parse Address",
    mileage: "0",
    gps: "6",
    gsm: "3",
    speed: "2",
    state: "Stopped",
    group: "Default Group",
    time: "2026-07-15 09:17:48",
  },
];

export default function ReportPage() {
  return (
    <div className="min-h-[calc(100vh-58px)] bg-[#f1f4f8] p-2">
      <section className="rounded-md bg-white">
        <div className="flex h-12 items-end gap-9 border-b border-[#e2e8f1] px-5">
          {["Device Overview", "Motion Overview", "Alert Overview"].map(
            (tab, index) => (
              <button
                key={tab}
                type="button"
                className={[
                  "h-12 border-b-2 px-1 text-[13px] font-medium",
                  index === 0
                    ? "border-[#367cf6] text-[#367cf6]"
                    : "border-transparent text-[#52698e]",
                ].join(" ")}
              >
                {tab}
              </button>
            ),
          )}
        </div>

        <div className="px-4 py-4">
          <RefreshCw className="h-4 w-4 text-[#367cf6]" />
          <div className="mt-2 flex flex-wrap justify-between gap-4">
            <StatusRing
              label="Total"
              value="100%"
              detail="Total 1"
              percentage={100}
              color="#7774ff"
            />
            <StatusRing
              label="Activated"
              value="100.00%"
              detail="Activated 1"
              percentage={100}
              color="#4c82ff"
            />
            <StatusRing
              label="Inactivated"
              value="0.00%"
              detail="Inactivated 0"
              percentage={0}
              color="#20d0a2"
            />
            <StatusRing
              label="Expired"
              value="0.00%"
              detail="Expired 0"
              percentage={0}
              color="#ff8a62"
            />
            <StatusRing
              label="Expiring soon"
              value="0.00%"
              detail="Expiring soon 0"
              percentage={0}
              color="#ff5575"
            />
          </div>
        </div>
      </section>

      <section className="mt-3 overflow-hidden rounded-md bg-white p-4">
        <div className="overflow-x-auto">
          <table className="w-full min-w-[1150px] text-center text-[12px]">
            <thead className="bg-[#edf1f7] text-[#405779]">
              <tr>
                {[
                  "No.",
                  "Device Name",
                  "Address",
                  "Mileage",
                  "GPS Positioning",
                  "GSM",
                  "Speed (km/h)",
                  "State",
                  "Group",
                  "Position Time",
                ].map((heading) => (
                  <th
                    key={heading}
                    className="border border-[#e2e8f1] px-3 py-3 font-semibold"
                  >
                    {heading}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {reportRows.map((row) => (
                <tr key={row.no} className="text-[#4f6385]">
                  <td className="border border-[#e2e8f1] px-3 py-3">{row.no}</td>
                  <td className="border border-[#e2e8f1] px-3 py-3">{row.device}</td>
                  <td className="border border-[#e2e8f1] px-3 py-3 text-[#367cf6]">
                    {row.address}
                  </td>
                  <td className="border border-[#e2e8f1] px-3 py-3">{row.mileage}</td>
                  <td className="border border-[#e2e8f1] px-3 py-3">{row.gps}</td>
                  <td className="border border-[#e2e8f1] px-3 py-3">{row.gsm}</td>
                  <td className="border border-[#e2e8f1] px-3 py-3">{row.speed}</td>
                  <td className="border border-[#e2e8f1] px-3 py-3">{row.state}</td>
                  <td className="border border-[#e2e8f1] px-3 py-3">{row.group}</td>
                  <td className="border border-[#e2e8f1] px-3 py-3">{row.time}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>
    </div>
  );
}