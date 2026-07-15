import {
  ChevronDown,
  Grid3X3,
  List,
  MapPin,
  Pencil,
  Search,
  Send,
  UserRoundCog,
} from "lucide-react";
import { ActionButton } from "@/components/ui/action-button";

const leftActions = [
  "Import device",
  "Renew",
  "Sell/move",
  "Update user expiration",
];

const centerActions = ["Send Command", "Batch settings", "Bind device"];

const rightActions = [
  "Disable",
  "Enable",
  "Batch operations",
  "Set group",
  "Allow activation",
];

export default function DevicePage() {
  return (
    <div className="min-h-[calc(100vh-var(--st-topbar-height))] bg-[#f4f6f9] p-2">
      <section className="min-h-[calc(100vh-var(--st-topbar-height)-16px)] rounded-[5px] bg-white px-3 pb-3 pt-2">
        <div className="grid gap-3 xl:grid-cols-[1.15fr_0.75fr_0.75fr_auto_auto_1fr]">
          <input
            className="h-8 rounded-[3px] border border-[#cfd8e7] px-3 text-[11px] outline-none focus:border-[#357cf4]"
            placeholder="IMEI(Press Enter for multiple lines)"
          />
          <input
            className="h-8 rounded-[3px] border border-[#cfd8e7] px-3 text-[11px] outline-none focus:border-[#357cf4]"
            placeholder="Device name"
          />
          <button
            type="button"
            className="flex h-8 items-center justify-between rounded-[3px] border border-[#cfd8e7] px-3 text-[11px] text-[#647696]"
          >
            All model
            <ChevronDown className="h-3.5 w-3.5" />
          </button>

          <ActionButton className="h-8 px-4 text-[12px]">
            <Search className="h-3.5 w-3.5" />
            Search
          </ActionButton>

          <ActionButton
            variant="outline"
            className="h-8 px-4 text-[12px]"
          >
            Reset
          </ActionButton>

          <button
            type="button"
            className="ml-auto flex items-center gap-1 text-[11px] text-[#357cf4]"
          >
            Advanced Search
            <ChevronDown className="h-3.5 w-3.5" />
          </button>
        </div>

        <div className="mt-4 grid gap-3 border-y border-[#e1e7f0] py-3 xl:grid-cols-[1.05fr_1fr_1.08fr]">
          <div className="flex flex-wrap items-center justify-center gap-2 border-r border-[#e1e7f0] px-3">
            {leftActions.map((label) => (
              <ActionButton key={label} className="h-8 px-4 text-[12px]">
                {label}
              </ActionButton>
            ))}
          </div>

          <div className="flex flex-wrap items-center justify-center gap-2 border-r border-[#e1e7f0] px-3">
            {centerActions.map((label, index) => (
              <ActionButton key={label} className="h-8 px-4 text-[12px]">
                {label}
                {index < 2 ? <ChevronDown className="h-3.5 w-3.5" /> : null}
              </ActionButton>
            ))}
          </div>

          <div className="flex flex-wrap items-center justify-center gap-2 px-3">
            {rightActions.map((label, index) => (
              <ActionButton key={label} className="h-8 px-4 text-[12px]">
                {label}
                {index === 2 ? <ChevronDown className="h-3.5 w-3.5" /> : null}
              </ActionButton>
            ))}
          </div>
        </div>

        <div className="mt-3 flex justify-end gap-2">
          <ActionButton
            variant="outline"
            className="h-8 px-4 text-[12px]"
          >
            Export
          </ActionButton>
          <ActionButton
            variant="outline"
            className="h-8 px-4 text-[12px]"
          >
            Export all
          </ActionButton>
          <button
            type="button"
            className="grid h-8 w-8 place-items-center rounded-[3px] text-[#405779] hover:bg-[#edf4ff]"
          >
            <Grid3X3 className="h-4 w-4" />
          </button>
        </div>

        <div className="mt-2 overflow-x-auto">
          <table className="w-full min-w-[1200px] text-center text-[10px]">
            <thead className="bg-[#edf1f7] text-[#405779]">
              <tr>
                <th className="w-12 px-3 py-3">
                  <input type="checkbox" aria-label="Select all devices" />
                </th>
                {[
                  "No.",
                  "Device name",
                  "IMEI",
                  "Device Model",
                  "Activated time",
                  "Subscription Expiration",
                  "Expiration Date(U)",
                  "Actions",
                ].map((heading) => (
                  <th key={heading} className="px-3 py-3 font-semibold">
                    {heading}
                  </th>
                ))}
              </tr>
            </thead>

            <tbody>
              <tr className="border-b border-[#e1e7f0] text-[#52698e]">
                <td className="px-3 py-3">
                  <input type="checkbox" aria-label="Select device 36-5958" />
                </td>
                <td className="px-3 py-3">1</td>
                <td className="px-3 py-3">36-5958</td>
                <td className="px-3 py-3 text-[#357cf4]">
                  868298066869554
                </td>
                <td className="px-3 py-3">GT06</td>
                <td className="px-3 py-3">2025-08-30 17:18:10</td>
                <td className="px-3 py-3">
                  2026-08-31(Expires in 47 days)
                </td>
                <td className="px-3 py-3">
                  2026-08-31(Expires in 47 days)
                </td>
                <td className="px-3 py-3">
                  <div className="flex items-center justify-center gap-4 text-[#357cf4]">
                    <Pencil className="h-3.5 w-3.5" />
                    <UserRoundCog className="h-3.5 w-3.5" />
                    <MapPin className="h-3.5 w-3.5" />
                    <List className="h-3.5 w-3.5" />
                    <Send className="h-3.5 w-3.5" />
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
    </div>
  );
}