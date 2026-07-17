import Link from "next/link";

type FeaturePlaceholderProps = {
  eyebrow: string;
  title: string;
  description: string;
};

export function FeaturePlaceholder({
  eyebrow,
  title,
  description,
}: FeaturePlaceholderProps) {
  return (
    <div className="mx-auto max-w-5xl">
      <div className="rounded-3xl border border-slate-200 bg-white p-8 shadow-sm md:p-12">
        <p className="text-xs font-bold uppercase tracking-[0.18em] text-teal-700">
          {eyebrow}
        </p>
        <h1 className="mt-4 text-3xl font-black tracking-tight text-slate-950 md:text-4xl">
          {title}
        </h1>
        <p className="mt-4 max-w-2xl text-base leading-7 text-slate-600">
          {description}
        </p>

        <div className="mt-8 rounded-2xl border border-dashed border-teal-300 bg-teal-50 p-5">
          <p className="font-semibold text-teal-950">
            Foundation route is ready.
          </p>
          <p className="mt-1 text-sm leading-6 text-teal-800">
            Authentication, API contracts, authorization, loading states, and
            production data will be implemented in the relevant development
            stage.
          </p>
        </div>

        <Link
          href="/dashboard"
          className="mt-8 inline-flex rounded-xl bg-slate-950 px-5 py-3 text-sm font-semibold text-white transition hover:bg-slate-800"
        >
          Return to dashboard
        </Link>
      </div>
    </div>
  );
}