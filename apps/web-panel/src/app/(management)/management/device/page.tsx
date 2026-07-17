import { DeviceManagementWorkspace } from "@/components/management/device-management-workspace";
import { canManageDealers } from "@/lib/auth/management-access";
import { requireManagementSession } from "@/lib/auth/server-session";

export default async function ManagementDevicePage() {
  const session = await requireManagementSession();
  const permissions = new Set(session.user.permissions);
  const platformWorkspace = canManageDealers(
    session.workspace,
  );

  return (
    <DeviceManagementWorkspace
      workspace={session.workspace}
      canViewDevices={permissions.has("device.view")}
      canViewDealers={permissions.has("dealer.view")}
      canViewCustomers={permissions.has("customer.view")}
      canRegisterDevices={
        platformWorkspace &&
        permissions.has("device.register")
      }
      canTransferDevices={permissions.has("device.remove")}
    />
  );
}