import { CustomerAssetWorkspace } from "@/components/customer/customer-asset-workspace";
import { requireCustomerSession } from "@/lib/auth/server-session";

export default async function DevicePage() {
  const session = await requireCustomerSession();
  const permissions = new Set(session.user.permissions);

  return (
    <CustomerAssetWorkspace
      view="device"
      canViewVehicles={permissions.has("vehicle.view")}
      canViewLocation={permissions.has("vehicle.location.view")}
      canViewHistory={permissions.has("vehicle.history.view")}
    />
  );
}