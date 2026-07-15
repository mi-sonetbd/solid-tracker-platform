import { DirectCustomerWorkspace } from "@/components/management/direct-customer-workspace";
import { canManageDealers } from "@/lib/auth/management-access";
import { requireManagementSession } from "@/lib/auth/server-session";

export default async function ManagementCustomersPage() {
  const session = await requireManagementSession();
  const permissions = new Set(session.user.permissions);
  const platformWorkspace = canManageDealers(session.workspace);

  return (
    <DirectCustomerWorkspace
      workspace={session.workspace}
      canCreateDirectCustomer={
        platformWorkspace &&
        permissions.has("customer.create")
      }
      canViewCustomers={permissions.has("customer.view")}
      canManageMembers={
        platformWorkspace &&
        permissions.has("customer.update")
      }
    />
  );
}