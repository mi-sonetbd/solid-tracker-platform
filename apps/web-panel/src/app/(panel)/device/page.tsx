import { CustomerDeviceWorkspace } from "@/components/customer/customer-device-workspace";
import { requireCustomerSession } from "@/lib/auth/server-session";

export default async function DevicePage() {
  const session = await requireCustomerSession();
  const permissions = new Set(
    session.user.permissions,
  );

  return (
    <CustomerDeviceWorkspace
      canViewVehicles={permissions.has("vehicle.view")}
    />
  );
}