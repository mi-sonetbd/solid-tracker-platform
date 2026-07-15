import Link from "next/link";
import { RadioTower } from "lucide-react";

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
      >
        Solid
      </span>
      <span
        className={[
          "font-black italic tracking-[-1.5px]",
          compact ? "text-[22px]" : "text-[31px]",
          lightBackground ? "text-[#ff9b24]" : "text-[#9fdcff]",
        ].join(" ")}
      >
        Tracker
      </span>
      <RadioTower
        className={[
          "ml-0.5",
          compact ? "h-[17px] w-[17px]" : "h-6 w-6",
          lightBackground ? "text-[#ff9b24]" : "text-[#9fdcff]",
        ].join(" ")}
        strokeWidth={2.4}
      />
    </span>
  );

  if (!href) {
    return content;
  }

  return <Link href={href}>{content}</Link>;
}