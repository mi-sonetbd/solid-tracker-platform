import { CustomerAlertWorkspace } from "@/components/customer/customer-alert-workspace";
import { requireCustomerSession } from "@/lib/auth/server-session";

type AlertPageProps = {
  searchParams: Promise<{
    vehicleId?: string;
  }>;
};

export default async function AlertPage({
  searchParams,
}: AlertPageProps) {
  const session = await requireCustomerSession();
  const permissions = new Set(
    session.user.permissions,
  );
  const parameters = await searchParams;

  return (
    <CustomerAlertWorkspace
      canViewVehicles={permissions.has("vehicle.view")}
      canViewLocation={permissions.has(
        "vehicle.location.view",
      )}
      initialVehicleId={parameters.vehicleId}
    />
  );
}