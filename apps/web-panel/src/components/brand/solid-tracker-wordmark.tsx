import Link from "next/link";
import { MapPin } from "lucide-react";

type SolidTrackerWordmarkProps = {
  href?: string;
  compact?: boolean;
  lightBackground?: boolean;
};

export function SolidTrackerWordmark({
  href = "/monitor",
  compact = false,
  lightBackground = true,
}: SolidTrackerWordmarkProps) {
  const content = (
    <span className="inline-flex items-center whitespace-nowrap">
      <span
        className={[
          "font-black italic tracking-[-1.5px]",
          compact ? "text-[22px]" : "text-[31px]",
          lightBackground ? "text-[#1295dc]" : "text-white",
        ].join(" ")}
      ><span>S</span><MapPin aria-hidden="true" className="solid-marker-o mx-[1px] inline-block h-[0.92em] w-[0.92em] -skew-x-12 align-[-0.08em] text-[#f59a23] stroke-[2.15]" /><span>lid</span></span>
      <span
        className={[
          "font-black italic tracking-[-1.5px]",
          compact ? "text-[22px]" : "text-[31px]",
          lightBackground ? "text-[#ff9b24]" : "text-[#9fdcff]",
        ].join(" ")}
      >
        Tracker
      </span>
    </span>
  );

  if (!href) {
    return content;
  }

  return <Link href={href}>{content}</Link>;
}