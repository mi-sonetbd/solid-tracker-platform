"use client";

import {
  ChevronDown,
  ChevronRight,
  Download,
  Search,
  Trash2,
  UserRound,
  UsersRound,
  X,
} from "lucide-react";

type SellMoveModalProps = {
  open: boolean;
  onClose: () => void;
};

export function SellMoveModal({
  open,
  onClose,
}: SellMoveModalProps) {
  if (!open) {
    return null;
  }

  return (
    <div className="fixed inset-0 z-[2000] grid place-items-center bg-[#17345f]/45 p-5">
      <section className="flex h-[min(760px,92vh)] w-full max-w-[1160px] flex-col overflow-hidden rounded-[8px] bg-white shadow-[0_28px_80px_rgba(18,44,86,0.3)]">
        <header className="flex h-14 items-center justify-between border-b border-[#dfe6ef] px-6">
          <h2 className="text-[17px] font-semibold text-[#344b72]">
            Sell/move
          </h2>
          <button
            type="button"
            onClick={onClose}
            className="text-[#71819c]"
          >
            <X className="h-5 w-5" />
          </button>
        </header>

        <div className="grid min-h-0 flex-1 grid-cols-2 gap-5 p-6">
          <section className="flex min-h-0 flex-col">
            <h3 className="text-[13px] font-semibold text-[#405779]">
              Selected devices: <span className="text-[#ff5575]">1</span>
            </h3>

            <div className="mt-4 flex h-10 rounded-[3px] border border-[#cfd8e7]">
              <input
                className="min-w-0 flex-1 border-0 bg-transparent px-4 text-[12px] outline-none"
                placeholder="IMEI (Press Enter for multiple lines)"
              />
              <button
                type="button"
                className="w-24 bg-[#357cf4] text-[12px] font-semibold text-white"
              >
                Add
              </button>
            </div>

            <div className="mt-3 flex-1 overflow-hidden rounded-[4px] border border-[#dfe6ef]">
              <table className="w-full text-left text-[12px]">
                <thead className="bg-[#edf2f8] text-[#405779]">
                  <tr>
                    <th className="px-4 py-3">IMEI</th>
                    <th className="px-4 py-3">Device name</th>
                    <th className="px-4 py-3">Account</th>
                    <th className="px-4 py-3">Actions</th>
                  </tr>
                </thead>
                <tbody>
                  <tr className="border-t border-[#dfe6ef] text-[#52698e]">
                    <td className="px-4 py-4">868298066786675</td>
                    <td className="px-4 py-4">GT06-86675</td>
                    <td className="px-4 py-4">the.faisalhaque</td>
                    <td className="px-4 py-4 text-[#357cf4]">
                      <Trash2 className="h-4 w-4" />
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </section>

          <section className="flex min-h-0 flex-col">
            <h3 className="text-[13px] font-semibold text-[#405779]">
              Transfer to: <span className="text-[#357cf4]">Solid Tracker</span>
            </h3>

            <label className="mt-4 flex h-10 rounded-[3px] border border-[#cfd8e7]">
              <input
                className="min-w-0 flex-1 border-0 bg-transparent px-4 text-[12px] outline-none"
                placeholder="Please enter customer name or account number"
              />
              <Search className="my-auto h-4 w-4 text-[#607392]" />
              <button
                type="button"
                className="ml-3 grid w-12 place-items-center bg-[#357cf4] text-white"
              >
                <Download className="h-4 w-4" />
              </button>
            </label>

            <div className="st-scrollbar mt-3 flex-1 overflow-y-auto rounded-[4px] border border-[#dfe6ef] p-3 text-[12px]">
              <div className="flex h-9 items-center gap-2 rounded bg-[#edf2f8] px-2 font-semibold">
                <ChevronDown className="h-4 w-4" />
                <UsersRound className="h-4 w-4 text-[#ff9b24]" />
                Solid Tracker (Stock 10 / Total 7276)
              </div>

              {["Admin", "Company", "Dealer"].map((label) => (
                <div
                  key={label}
                  className="ml-6 flex h-9 items-center gap-2 text-[#52698e]"
                >
                  <ChevronRight className="h-3.5 w-3.5" />
                  <UserRound className="h-4 w-4 text-[#ff9b24]" />
                  {label}
                </div>
              ))}

              <div className="ml-6 flex h-9 items-center gap-2 rounded bg-[#eaf2ff] px-2 text-[#357cf4]">
                <ChevronDown className="h-3.5 w-3.5" />
                <UserRound className="h-4 w-4 text-[#ff9b24]" />
                Khaza Faisal Haque
              </div>

              {[
                "Forhad Hasan Mamun",
                "M. M. Golam Mostofa",
                "Najim Uddin",
                "Sonet",
              ].map((name) => (
                <button
                  key={name}
                  type="button"
                  className="ml-12 flex h-9 items-center gap-2 text-[#52698e] hover:text-[#357cf4]"
                >
                  <UserRound className="h-4 w-4 text-[#29a8ef]" />
                  {name}
                </button>
              ))}
            </div>
          </section>
        </div>

        <footer className="flex h-16 items-center justify-end gap-3 border-t border-[#dfe6ef] px-6">
          <button
            type="button"
            onClick={onClose}
            className="h-9 rounded-[3px] border border-[#cfd8e7] px-6 text-[12px] text-[#52698e]"
          >
            Cancel
          </button>
          <button
            type="button"
            className="h-9 rounded-[3px] bg-[#357cf4] px-6 text-[12px] font-semibold text-white"
          >
            Confirm
          </button>
        </footer>
      </section>
    </div>
  );
}