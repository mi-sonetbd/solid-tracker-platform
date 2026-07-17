import { BarChart3 } from "lucide-react";
import { ManagementPlaceholder } from "@/components/management/management-placeholder";

export default function ManagementReportPage() {
  return (
    <ManagementPlaceholder
      title="Management Reports"
      description="Dealer, customer, device, billing, and operational reports will be connected after the management data APIs are integrated."
      icon={BarChart3}
    />
  );
}