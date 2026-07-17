"use client";

import type {
  TrackingMapBasemap,
} from "@/components/map/tracking-map-types";

type CustomerMapProviderSelectorProps = {
  id: string;
  open: boolean;
  value: TrackingMapBasemap;
  onChange: (
    value: TrackingMapBasemap,
  ) => void;
};

const providerOptions: Array<{
  value: TrackingMapBasemap;
  label: string;
  detail?: string;
}> = [
  {
    value: "google-roadmap",
    label: "Google Map (Street)",
  },
  {
    value: "google-hybrid",
    label: "Google Map (Hybrid)",
  },
  {
    value: "google-satellite",
    label: "Google Map (Satellite)",
  },
  {
    value: "openstreet-hybrid",
    label: "OpenStreet Map (Hybrid)",
    detail: "Esri imagery + labels",
  },
  {
    value: "openstreet-satellite",
    label: "OpenStreet Map (Satellite)",
    detail: "Esri imagery",
  },
];

export function CustomerMapProviderSelector({
  id,
  open,
  value,
  onChange,
}: CustomerMapProviderSelectorProps) {
  if (!open) {
    return null;
  }

  return (
    <div
      id={`${id}-panel`}
      role="radiogroup"
      aria-label="Map provider"
      className="absolute right-12 top-[150px] z-[1200] w-[228px] rounded-[5px] border border-[#d6deea] bg-white px-3 py-2.5 shadow-[0_4px_14px_rgba(35,61,102,0.22)]"
    >
      {providerOptions.map((option) => {
        const selected =
          option.value === value;

        return (
          <button
            key={option.value}
            type="button"
            role="radio"
            aria-checked={selected}
            onClick={() =>
              onChange(option.value)
            }
            className="flex w-full items-start gap-2 rounded px-0.5 py-1.5 text-left transition hover:bg-[#f2f6fc]"
          >
            <span
              aria-hidden="true"
              className={[
                "mt-0.5 grid h-[18px] w-[18px] shrink-0 place-items-center rounded-full border",
                selected
                  ? "border-[#357cf4]"
                  : "border-[#8ea0bb]",
              ].join(" ")}
            >
              {selected ? (
                <span className="h-[10px] w-[10px] rounded-full bg-[#357cf4]" />
              ) : null}
            </span>

            <span className="min-w-0">
              <span className="block text-[13px] font-medium leading-5 text-[#435878]">
                {option.label}
              </span>

              {option.detail ? (
                <span className="block text-[10px] leading-4 text-[#8a9ab2]">
                  {option.detail}
                </span>
              ) : null}
            </span>
          </button>
        );
      })}
    </div>
  );
}