import type { ButtonHTMLAttributes, ReactNode } from "react";

type ActionButtonProps = ButtonHTMLAttributes<HTMLButtonElement> & {
  children: ReactNode;
  variant?: "primary" | "outline" | "ghost";
};

export function ActionButton({
  children,
  variant = "primary",
  className = "",
  ...props
}: ActionButtonProps) {
  const variantClass = {
    primary: "border-[#367cf6] bg-[#367cf6] text-white hover:bg-[#2464d8]",
    outline:
      "border-[#367cf6] bg-white text-[#367cf6] hover:bg-[#edf4ff]",
    ghost: "border-transparent bg-transparent text-[#52698e] hover:bg-white",
  }[variant];

  return (
    <button
      type="button"
      className={[
        "inline-flex h-9 items-center justify-center gap-2 rounded-[3px] border px-4 text-[13px] font-semibold transition",
        variantClass,
        className,
      ].join(" ")}
      {...props}
    >
      {children}
    </button>
  );
}