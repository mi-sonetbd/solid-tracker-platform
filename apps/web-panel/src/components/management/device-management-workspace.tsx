"use client";

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
import { useState } from "react";
import { AccountTree } from "@/components/management/account-tree";
import { SellMoveModal } from "@/components/management/sell-move-modal";

const deviceRows = [
  {
    account: "the.faisalhaque",
    name: "GT06-86675",
    imei: "868298066786675",
    model: "GT06",
    activated: "2026-07-07 22:32:37",
    subscription: "2027-07-08",
    expiration: "2027-07-08",
  },
  {
    account: "the.faisalhaque",
    name: "GT06-48388",
    imei: "867857033848388",
    model: "GT06",
    activated: "2025-01-12 22:46:45",
    subscription: "Expired",
    expiration: "Expired",
  },
  {
    account: "the.faisalhaque",
    name: "Kanak Vai test",
    imei: "867857033848180",
    model: "GT06",
    activated: "2025-01-04 01:49:51",
    subscription: "Expired",
    expiration: "Expired",
  },
  {
    account: "the.faisalhaque",
    name: "GT06-48172",
    imei: "867857033848172",
    model: "GT06",
    activated: "2025-01-01 12:33:24",
    subscription: "Expired",
    expiration: "Expired",
  },
  {
    account: "the.faisalhaque",
    name: "WETRACK2-46293",
    imei: "358735073046293",
    model: "WETRACK2",
    activated: "2018-08-30 02:27:09",
    subscription: "Expired",
    expiration: "Expired",
  },
];

function BlueButton({
  children,
  onClick,
}: {
  children: React.ReactNode;
  onClick?: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="flex h-8 items-center gap-1 rounded-[3px] bg-[#357cf4] px-4 text-[11px] font-semibold text-white hover:bg-[#2766d5]"
    >
      {children}
    </button>
  );
}

export function DeviceManagementWorkspace() {
  const [sellMoveOpen, setSellMoveOpen] = useState(false);

  return (
    <>
      <div className="flex h-[calc(100vh-var(--st-topbar-height))] min-w-[1380px] overflow-hidden p-2">
        <AccountTree />

        <section className="st-scrollbar min-w-0 flex-1 overflow-auto rounded-r-[6px] bg-white p-3">
          <div className="grid gap-3 xl:grid-cols-[1.1fr_0.7fr_0.7fr_auto_auto_auto_1fr]">
            <input
              className="h-8 rounded-[3px] border border-[#cfd8e7] px-3 text-[11px] outline-none"
              placeholder="IMEI (Press Enter for multiple lines)"
            />
            <input
              className="h-8 rounded-[3px] border border-[#cfd8e7] px-3 text-[11px] outline-none"
              placeholder="Device name"
            />
            <button
              type="button"
              className="flex h-8 items-center justify-between rounded-[3px] border border-[#cfd8e7] px-3 text-[11px] text-[#52698e]"
            >
              All model
              <ChevronDown className="h-3.5 w-3.5" />
            </button>
            <label className="flex items-center gap-2 text-[11px] text-[#52698e]">
              <input type="checkbox" />
              Sub-account devices
            </label>
            <BlueButton>
              <Search className="h-3.5 w-3.5" />
              Search
            </BlueButton>
            <button
              type="button"
              className="h-8 rounded-[3px] border border-[#357cf4] px-4 text-[11px] text-[#357cf4]"
            >
              Reset
            </button>
            <button
              type="button"
              className="ml-auto flex items-center gap-1 text-[11px] text-[#357cf4]"
            >
              Advanced Search
              <ChevronDown className="h-3.5 w-3.5" />
            </button>
          </div>

          <div className="mt-4 grid gap-3 border-y border-[#e2e8f1] py-3 xl:grid-cols-[0.95fr_1fr_1.15fr]">
            <div className="flex flex-wrap justify-center gap-2 border-r border-[#e2e8f1] px-3">
              <BlueButton>Import device</BlueButton>
              <BlueButton>Renew</BlueButton>
              <BlueButton onClick={() => setSellMoveOpen(true)}>
                Sell/move
              </BlueButton>
              <BlueButton>Update user expiration</BlueButton>
            </div>

            <div className="flex flex-wrap justify-center gap-2 border-r border-[#e2e8f1] px-3">
              <BlueButton>
                Send Command
                <ChevronDown className="h-3.5 w-3.5" />
              </BlueButton>
              <BlueButton>
                Batch settings
                <ChevronDown className="h-3.5 w-3.5" />
              </BlueButton>
              <BlueButton>Bind device</BlueButton>
            </div>

            <div className="flex flex-wrap justify-center gap-2 px-3">
              <BlueButton>Disable</BlueButton>
              <BlueButton>Enable</BlueButton>
              <BlueButton>
                Batch operations
                <ChevronDown className="h-3.5 w-3.5" />
              </BlueButton>
              <BlueButton>Set group</BlueButton>
              <BlueButton>Allow activation</BlueButton>
            </div>
          </div>

          <div className="mt-3 flex justify-end gap-2">
            <button
              type="button"
              className="h-8 rounded-[3px] border border-[#cfd8e7] px-4 text-[11px] text-[#52698e]"
            >
              Export
            </button>
            <button
              type="button"
              className="h-8 rounded-[3px] border border-[#cfd8e7] px-4 text-[11px] text-[#52698e]"
            >
              Export all
            </button>
            <button
              type="button"
              className="grid h-8 w-8 place-items-center text-[#52698e]"
            >
              <Grid3X3 className="h-4 w-4" />
            </button>
          </div>

          <div className="mt-2 overflow-x-auto">
            <table className="w-full min-w-[1260px] text-center text-[10px]">
              <thead className="bg-[#edf2f8] text-[#405779]">
                <tr>
                  <th className="w-12 px-3 py-3">
                    <input type="checkbox" />
                  </th>
                  {[
                    "No.",
                    "Account",
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
                {deviceRows.map((device, index) => (
                  <tr
                    key={device.imei}
                    className="border-b border-[#e2e8f1] text-[#52698e]"
                  >
                    <td className="px-3 py-4">
                      <input type="checkbox" />
                    </td>
                    <td className="px-3 py-4">{index + 1}</td>
                    <td className="px-3 py-4">{device.account}</td>
                    <td className="px-3 py-4">{device.name}</td>
                    <td className="px-3 py-4 text-[#357cf4]">
                      {device.imei}
                    </td>
                    <td className="px-3 py-4">{device.model}</td>
                    <td className="px-3 py-4">{device.activated}</td>
                    <td className="px-3 py-4">{device.subscription}</td>
                    <td className="px-3 py-4">{device.expiration}</td>
                    <td className="px-3 py-4">
                      <div className="flex items-center justify-center gap-4 text-[#357cf4]">
                        <Pencil className="h-4 w-4" />
                        <UserRoundCog className="h-4 w-4" />
                        <MapPin className="h-4 w-4" />
                        <List className="h-4 w-4" />
                        <Send className="h-4 w-4" />
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>
      </div>

      <SellMoveModal
        open={sellMoveOpen}
        onClose={() => setSellMoveOpen(false)}
      />
    </>
  );
}