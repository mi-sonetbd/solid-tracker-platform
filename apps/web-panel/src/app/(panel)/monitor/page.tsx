import { CustomerMonitorWorkspace } from "@/components/customer/customer-monitor-workspace";
import { requireCustomerSession } from "@/lib/auth/server-session";

type MonitorPageProps = {
  searchParams: Promise<{
    vehicleId?: string;
  }>;
};

export default async function MonitorPage({
  searchParams,
}: MonitorPageProps) {
  const session = await requireCustomerSession();
  const permissions = new Set(
    session.user.permissions,
  );
  const parameters = await searchParams;

  return (
    <CustomerMonitorWorkspace
      canViewVehicles={permissions.has("vehicle.view")}
      canViewLocation={permissions.has(
        "vehicle.location.view",
      )}
      initialVehicleId={parameters.vehicleId}
    />
  );
}