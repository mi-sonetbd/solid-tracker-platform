import { CustomerReportWorkspace } from "@/components/customer/customer-report-workspace";
import { requireCustomerSession } from "@/lib/auth/server-session";

export default async function ReportPage() {
  const session = await requireCustomerSession();
  const permissions = new Set(
    session.user.permissions,
  );

  return (
    <CustomerReportWorkspace
      canViewVehicles={permissions.has("vehicle.view")}
      canViewHistory={permissions.has(
        "vehicle.history.view",
      )}
    />
  );
}