import { AccountManagementWorkspace } from "@/components/management/account-management-workspace";
import {
  canManageCustomers,
  canManageDealers,
} from "@/lib/auth/management-access";
import { requireManagementSession } from "@/lib/auth/server-session";

export default async function ManagementAccountsPage() {
  const session = await requireManagementSession();
  const permissions = new Set(session.user.permissions);

  return (
    <AccountManagementWorkspace
      workspace={session.workspace}
      canCreateDealer={
        canManageDealers(session.workspace) &&
        permissions.has("dealer.manage")
      }
      canViewDealers={permissions.has("dealer.view")}
      canCreateCustomer={
        canManageCustomers(session.workspace) &&
        permissions.has("customer.manage")
      }
      canManageDealerStaff={permissions.has(
        "dealer.staff.manage",
      )}
    />
  );
}