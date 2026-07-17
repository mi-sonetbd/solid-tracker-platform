import { ManagementMonitorWorkspace } from "@/components/management/management-monitor-workspace";
import { requireManagementSession } from "@/lib/auth/server-session";

export default async function ManagementMonitorPage() {
  const session = await requireManagementSession();
  const permissions = new Set(
    session.user.permissions,
  );

  return (
    <ManagementMonitorWorkspace
      workspace={session.workspace}
      canViewDealers={permissions.has(
        "dealer.view",
      )}
      canViewCustomers={permissions.has(
        "customer.view",
      )}
      canViewVehicles={permissions.has(
        "vehicle.view",
      )}
      canViewLocation={permissions.has(
        "vehicle.location.view",
      )}
    />
  );
}