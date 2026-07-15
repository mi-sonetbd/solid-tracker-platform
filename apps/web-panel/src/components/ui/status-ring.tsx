import type { CSSProperties } from "react";

type StatusRingProps = {
  label: string;
  value: string;
  detail: string;
  percentage: number;
  color: string;
};

export function StatusRing({
  label,
  value,
  detail,
  percentage,
  color,
}: StatusRingProps) {
  return (
    <article className="flex min-w-[150px] flex-1 flex-col items-center py-2">
      <h3 className="text-[13px] font-semibold text-[#42577d]">{label}</h3>

      <div
        className="st-ring relative mt-4 h-[96px] w-[96px] rounded-full"
        style={
          {
            "--value": `${percentage}%`,
            "--ring-color": color,
          } as CSSProperties
        }
      >
        <div
          className="absolute inset-0 z-10 grid place-items-center text-[15px] font-semibold"
          style={{ color }}
        >
          {value}
        </div>
      </div>

      <p className="mt-2.5 flex items-center gap-2 text-[11px] text-[#647696]">
        <span
          className="h-2 w-2 rounded-full"
          style={{ backgroundColor: color }}
        />
        {detail}
      </p>
    </article>
  );
}