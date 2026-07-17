import { CustomerFleetWorkspace } from "@/components/customer/customer-fleet-workspace";
import { requireCustomerSession } from "@/lib/auth/server-session";

export default async function FleetPage() {
  const session = await requireCustomerSession();
  const permissions = new Set(
    session.user.permissions,
  );

  return (
    <CustomerFleetWorkspace
      canViewVehicles={permissions.has("vehicle.view")}
    />
  );
}