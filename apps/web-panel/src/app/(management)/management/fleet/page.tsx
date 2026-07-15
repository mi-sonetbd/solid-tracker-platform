import { CarFront } from "lucide-react";
import { ManagementPlaceholder } from "@/components/management/management-placeholder";

export default function ManagementFleetPage() {
  return (
    <ManagementPlaceholder
      title="Management Fleet"
      description="Fleet, driver, route-plan, and RFID administration will be connected in a dedicated management workflow."
      icon={CarFront}
    />
  );
}