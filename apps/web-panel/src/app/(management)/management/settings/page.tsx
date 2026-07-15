import { Settings2 } from "lucide-react";
import { ManagementPlaceholder } from "@/components/management/management-placeholder";

export default function ManagementSettingsPage() {
  return (
    <ManagementPlaceholder
      title="Management Settings"
      description="Profile, security, notification, account, and workspace preferences will be configured here. Role-specific settings remain limited by backend permissions."
      icon={Settings2}
    />
  );
}