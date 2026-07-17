import type {
  SVGProps,
} from "react";

type CustomerMapFullscreenIconProps =
  SVGProps<SVGSVGElement> & {
    size?: number | string;
    strokeWidth?: number | string;
  };

export function CustomerMapFullscreenIcon({
  size = 17,
  strokeWidth = 1.9,
  className,
  ...props
}: CustomerMapFullscreenIconProps) {
  return (
    <svg
      viewBox="0 0 24 24"
      width={size}
      height={size}
      fill="none"
      className={className}
      aria-hidden="true"
      {...props}
    >
      <g className="group-aria-[pressed=true]:hidden">
        <path
          d="M8 3H3v5M16 3h5v5M8 21H3v-5M16 21h5v-5"
          stroke="currentColor"
          strokeWidth={strokeWidth}
          strokeLinecap="round"
          strokeLinejoin="round"
        />
      </g>

      <g className="hidden group-aria-[pressed=true]:block">
        <path
          d="M8 8H3M8 8V3M16 8h5M16 8V3M8 16H3M8 16v5M16 16h5M16 16v5"
          stroke="currentColor"
          strokeWidth={strokeWidth}
          strokeLinecap="round"
          strokeLinejoin="round"
        />
      </g>
    </svg>
  );
}
