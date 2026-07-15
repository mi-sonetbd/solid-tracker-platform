import {
  Building2,
  CirclePlus,
  ShieldCheck,
  UserRoundPlus,
  UsersRound,
} from "lucide-react";
import { AccountTree } from "@/components/management/account-tree";
import { LogoutButton } from "@/components/auth/logout-button";
import {
  canManageCustomers,
  canManageDealers,
} from "@/lib/auth/management-access";
import { requireManagementSession } from "@/lib/auth/server-session";

export default async function ManagementAccountsPage() {
  const session = await requireManagementSession();
  const dealerAccess = canManageDealers(session.workspace);
  const customerAccess = canManageCustomers(session.workspace);

  return (
    <div className="flex h-[calc(100vh-var(--st-topbar-height))] min-w-[1180px] overflow-hidden p-2">
      <AccountTree />

      <section className="st-scrollbar min-w-0 flex-1 overflow-auto rounded-r-[6px] bg-white p-5">
        <div className="flex items-start justify-between border-b border-[#e2e8f1] pb-4">
          <div>
            <h1 className="text-[18px] font-semibold text-[#344b72]">
              Account Management
            </h1>
            <p className="mt-1 text-[12px] text-[#71819c]">
              Create and organize dealers, customer accounts, and account-level access.
            </p>
          </div>
          <LogoutButton />
        </div>

        <div className="mt-5 grid gap-4 lg:grid-cols-3">
          <article className="rounded-[6px] border border-[#dfe6ef] p-5">
            <div className="grid h-11 w-11 place-items-center rounded-full bg-[#eaf2ff] text-[#357cf4]">
              <Building2 className="h-5 w-5" />
            </div>
            <h2 className="mt-4 text-[14px] font-semibold text-[#405779]">
              Dealer Account
            </h2>
            <p className="mt-2 min-h-12 text-[11px] leading-5 text-[#71819c]">
              Create dealers and assign stock, managers, customers, and operational scope.
            </p>
            <button
              type="button"
              disabled={!dealerAccess}
              className="mt-4 flex h-9 items-center gap-2 rounded-[3px] bg-[#357cf4] px-4 text-[11px] font-semibold text-white disabled:cursor-not-allowed disabled:bg-[#b8c7dc]"
            >
              <CirclePlus className="h-4 w-4" />
              Add Dealer
            </button>
          </article>

          <article className="rounded-[6px] border border-[#dfe6ef] p-5">
            <div className="grid h-11 w-11 place-items-center rounded-full bg-[#eaf2ff] text-[#357cf4]">
              <UserRoundPlus className="h-5 w-5" />
            </div>
            <h2 className="mt-4 text-[14px] font-semibold text-[#405779]">
              Customer Account
            </h2>
            <p className="mt-2 min-h-12 text-[11px] leading-5 text-[#71819c]">
              Add a Customer, create login access, and place the account under the correct dealer.
            </p>
            <button
              type="button"
              disabled={!customerAccess}
              className="mt-4 flex h-9 items-center gap-2 rounded-[3px] bg-[#357cf4] px-4 text-[11px] font-semibold text-white disabled:cursor-not-allowed disabled:bg-[#b8c7dc]"
            >
              <CirclePlus className="h-4 w-4" />
              Add Customer
            </button>
          </article>

          <article className="rounded-[6px] border border-[#dfe6ef] p-5">
            <div className="grid h-11 w-11 place-items-center rounded-full bg-[#eaf2ff] text-[#357cf4]">
              <UsersRound className="h-5 w-5" />
            </div>
            <h2 className="mt-4 text-[14px] font-semibold text-[#405779]">
              Account Users
            </h2>
            <p className="mt-2 min-h-12 text-[11px] leading-5 text-[#71819c]">
              Add dealer managers, customer members, and scoped operational roles.
            </p>
            <button
              type="button"
              className="mt-4 flex h-9 items-center gap-2 rounded-[3px] bg-[#357cf4] px-4 text-[11px] font-semibold text-white"
            >
              <CirclePlus className="h-4 w-4" />
              Add User
            </button>
          </article>
        </div>

        <section className="mt-5 rounded-[6px] border border-[#dfe6ef]">
          <header className="flex items-center justify-between border-b border-[#e2e8f1] px-5 py-4">
            <div className="flex items-center gap-2">
              <ShieldCheck className="h-5 w-5 text-[#357cf4]" />
              <h2 className="text-[14px] font-semibold text-[#405779]">
                Role-aware access
              </h2>
            </div>
            <span className="rounded-full bg-[#eaf2ff] px-3 py-1 text-[10px] font-semibold text-[#357cf4]">
              {session.workspace}
            </span>
          </header>

          <div className="grid gap-3 p-5 md:grid-cols-2">
            <div className="rounded-[5px] bg-[#f5f8fc] p-4 text-[11px] leading-5 text-[#52698e]">
              <strong>Dealer creation:</strong>{" "}
              {dealerAccess ? "Allowed" : "Not allowed for this workspace"}
            </div>
            <div className="rounded-[5px] bg-[#f5f8fc] p-4 text-[11px] leading-5 text-[#52698e]">
              <strong>Customer creation:</strong>{" "}
              {customerAccess ? "Allowed" : "Not allowed for this workspace"}
            </div>
          </div>
        </section>
      </section>
    </div>
  );
}