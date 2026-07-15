import { AccountManagementWorkspace } from "@/components/management/account-management-workspace";
import {
  canManageCustomers,
  canManageDealers,
} from "@/lib/auth/management-access";
import { requireManagementSession } from "@/lib/auth/server-session";

export default async function ManagementAccountsPage() {
  const session = await requireManagementSession();
  const permissions = new Set(session.user.permissions);
  const platformWorkspace = canManageDealers(session.workspace);

  return (
    <AccountManagementWorkspace
      workspace={session.workspace}
      canCreateDealer={platformWorkspace && permissions.has("dealer.manage")}
      canViewDealers={permissions.has("dealer.view")}
      canCreateCustomer={
        canManageCustomers(session.workspace) &&
        permissions.has("customer.create")
      }
      canViewCustomers={permissions.has("customer.view")}
      canManageDealerStaff={permissions.has("dealer.staff.manage")}
      canManageCustomerMembers={permissions.has("customer.update")}
      canChooseCustomerAssignment={platformWorkspace}
    />
  );
}