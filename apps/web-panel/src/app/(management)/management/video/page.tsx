import { Video } from "lucide-react";
import { ManagementPlaceholder } from "@/components/management/management-placeholder";

export default function ManagementVideoPage() {
  return (
    <ManagementPlaceholder
      title="Management Video"
      description="Video-capable device operations will be added only for supported hardware and authorized management roles."
      icon={Video}
    />
  );
}