import type { LucideIcon } from "lucide-react";

type ManagementPlaceholderProps = {
  title: string;
  description: string;
  icon: LucideIcon;
};

export function ManagementPlaceholder({
  title,
  description,
  icon: Icon,
}: ManagementPlaceholderProps) {
  return (
    <main className="grid min-h-[calc(100vh-var(--st-topbar-height))] place-items-center p-8">
      <section className="w-full max-w-xl rounded-[8px] bg-white p-8 text-center shadow-sm">
        <div className="mx-auto grid h-16 w-16 place-items-center rounded-full bg-[#eaf2ff] text-[#357cf4]">
          <Icon className="h-8 w-8" />
        </div>
        <h1 className="mt-5 text-xl font-semibold text-[#344b72]">
          {title}
        </h1>
        <p className="mx-auto mt-3 max-w-md text-[12px] leading-6 text-[#71819c]">
          {description}
        </p>
      </section>
    </main>
  );
}