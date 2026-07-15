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
    <article className="flex min-w-[170px] flex-1 flex-col items-center py-3">
      <h3 className="text-[14px] font-semibold text-[#42577d]">{label}</h3>
      <div
        className="st-ring relative mt-5 h-[108px] w-[108px] rounded-full"
        style={
          {
            "--value": `${percentage}%`,
            "--ring-color": color,
          } as React.CSSProperties
        }
      >
        <div className="absolute inset-0 z-10 grid place-items-center text-[17px] font-semibold" style={{ color }}>
          {value}
        </div>
      </div>
      <p className="mt-3 flex items-center gap-2 text-[13px] text-[#647696]">
        <span
          className="h-2.5 w-2.5 rounded-full"
          style={{ backgroundColor: color }}
        />
        {detail}
      </p>
    </article>
  );
}