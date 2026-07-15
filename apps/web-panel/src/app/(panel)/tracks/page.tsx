import { CustomerTracksWorkspace } from "@/components/customer/customer-tracks-workspace";
import { requireCustomerSession } from "@/lib/auth/server-session";

type TracksPageProps = {
  searchParams: Promise<{
    vehicleId?: string;
  }>;
};

export default async function TracksPage({
  searchParams,
}: TracksPageProps) {
  const session = await requireCustomerSession();
  const permissions = new Set(
    session.user.permissions,
  );
  const parameters = await searchParams;

  return (
    <CustomerTracksWorkspace
      canViewVehicles={permissions.has("vehicle.view")}
      canViewLocation={permissions.has(
        "vehicle.location.view",
      )}
      initialVehicleId={parameters.vehicleId}
    />
  );
}