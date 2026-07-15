"use client";

import {
  Building2,
  ChevronDown,
  ChevronRight,
  Download,
  Search,
  UserRound,
  UsersRound,
} from "lucide-react";
import { useState } from "react";

type AccountTreeProps = {
  selectedAccount?: string;
  compact?: boolean;
};

const customerAccounts = [
  { name: "Forhad Hasan Mamun", stock: 1, total: 1 },
  { name: "M. M. Golam Mostofa", stock: 1, total: 1 },
  { name: "Najim Uddin", stock: 2, total: 2 },
  { name: "Sonet", stock: 0, total: 0 },
];

export function AccountTree({
  selectedAccount = "Khaza Faisal Haque",
  compact = false,
}: AccountTreeProps) {
  const [rootOpen, setRootOpen] = useState(true);
  const [customerOpen, setCustomerOpen] = useState(true);

  return (
    <aside
      className={[
        "flex h-full min-h-0 flex-col border-r border-[#dfe6ef] bg-white",
        compact ? "w-[300px]" : "w-[340px]",
      ].join(" ")}
    >
      <div className="flex h-12 items-center justify-between border-b border-[#e2e8f1] px-4">
        <h2 className="text-[13px] font-semibold text-[#344b72]">
          Account List
        </h2>
        <button
          type="button"
          className="text-[#607392]"
          aria-label="Collapse account list"
        >
          <ChevronRight className="h-4 w-4" />
        </button>
      </div>

      <div className="p-3">
        <label className="flex h-8 items-center rounded-[3px] border border-[#cfd8e7]">
          <input
            className="min-w-0 flex-1 border-0 bg-transparent px-3 text-[11px] outline-none placeholder:text-[#8b9ab4]"
            placeholder="Please enter customer name or account"
          />
          <Search className="h-4 w-4 text-[#607392]" />
          <button
            type="button"
            className="grid h-8 w-10 place-items-center bg-[#357cf4] text-white"
          >
            <Download className="h-4 w-4" />
          </button>
        </label>
      </div>

      <div className="st-scrollbar flex-1 overflow-y-auto px-3 pb-3 text-[11px]">
        <button
          type="button"
          onClick={() => setRootOpen((value) => !value)}
          className="flex h-9 w-full items-center gap-2 rounded-[3px] bg-[#edf2f8] px-2 text-left font-semibold text-[#405779]"
        >
          {rootOpen ? (
            <ChevronDown className="h-3.5 w-3.5" />
          ) : (
            <ChevronRight className="h-3.5 w-3.5" />
          )}
          <UsersRound className="h-4 w-4 text-[#ff9b24]" />
          <span className="truncate">
            Solid Tracker (Stock 10 / Total 7276)
          </span>
        </button>

        {rootOpen ? (
          <div className="ml-5 mt-1 space-y-1">
            {[
              ["Admin", "0 / 308", UserRound],
              ["Company", "0 / 2359", Building2],
              ["Dealer", "1 / 4590", UsersRound],
            ].map(([label, value, Icon]) => (
              <button
                key={String(label)}
                type="button"
                className="flex h-8 w-full items-center gap-2 rounded-[3px] px-2 text-left text-[#52698e] hover:bg-[#f1f5fb]"
              >
                <ChevronRight className="h-3 w-3" />
                <Icon className="h-4 w-4 text-[#ff9b24]" />
                <span>{String(label)}</span>
                <span className="text-[#8b9ab4]">({String(value)})</span>
              </button>
            ))}

            <button
              type="button"
              onClick={() => setCustomerOpen((value) => !value)}
              className={[
                "flex h-8 w-full items-center gap-2 rounded-[3px] px-2 text-left",
                selectedAccount === "Khaza Faisal Haque"
                  ? "bg-[#eaf2ff] text-[#357cf4]"
                  : "text-[#52698e] hover:bg-[#f1f5fb]",
              ].join(" ")}
            >
              {customerOpen ? (
                <ChevronDown className="h-3 w-3" />
              ) : (
                <ChevronRight className="h-3 w-3" />
              )}
              <UserRound className="h-4 w-4 text-[#ff9b24]" />
              <span>Khaza Faisal Haque</span>
              <span className="text-[#8b9ab4]">(5 / 9)</span>
            </button>

            {customerOpen ? (
              <div className="ml-6 space-y-1">
                {customerAccounts.map((account) => (
                  <button
                    key={account.name}
                    type="button"
                    className="flex h-8 w-full items-center gap-2 rounded-[3px] px-2 text-left text-[#52698e] hover:bg-[#f1f5fb]"
                  >
                    <UserRound className="h-4 w-4 text-[#29a8ef]" />
                    <span className="truncate">{account.name}</span>
                    <span className="text-[#8b9ab4]">
                      ({account.stock}/{account.total})
                    </span>
                  </button>
                ))}
              </div>
            ) : null}
          </div>
        ) : null}
      </div>
    </aside>
  );
}