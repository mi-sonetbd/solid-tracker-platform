import type {
  SVGProps,
} from "react";

type CustomerMapTrafficLightIconProps =
  SVGProps<SVGSVGElement> & {
    size?: number | string;
    strokeWidth?: number | string;
  };

export function CustomerMapTrafficLightIcon({
  size = 16,
  strokeWidth = 1.8,
  className,
  ...props
}: CustomerMapTrafficLightIconProps) {
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
      <rect
        x="7"
        y="2.5"
        width="10"
        height="19"
        rx="3"
        stroke="currentColor"
        strokeWidth={strokeWidth}
      />
      <circle
        cx="12"
        cy="7"
        r="1.65"
        fill="currentColor"
      />
      <circle
        cx="12"
        cy="12"
        r="1.65"
        fill="currentColor"
      />
      <circle
        cx="12"
        cy="17"
        r="1.65"
        fill="currentColor"
      />
      <path
        d="M4.5 7H7M17 7H19.5M4.5 17H7M17 17H19.5"
        stroke="currentColor"
        strokeWidth={strokeWidth}
        strokeLinecap="round"
      />
    </svg>
  );
}
