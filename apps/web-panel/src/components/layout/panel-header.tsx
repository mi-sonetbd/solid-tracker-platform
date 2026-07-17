export function PanelHeader() {
  return (
    <header className="sticky top-0 z-20 border-b border-slate-200 bg-white/95 px-5 py-4 backdrop-blur md:px-8">
      <div className="mx-auto flex max-w-[1600px] items-center justify-between gap-4">
        <div>
          <p className="text-xs font-bold uppercase tracking-[0.16em] text-teal-700">
            Solid Tracker
          </p>
          <p className="text-sm text-slate-500">
            Professional GPS tracking operations
          </p>
        </div>

        <div className="flex items-center gap-3">
          <span className="hidden rounded-full bg-emerald-50 px-3 py-1.5 text-xs font-semibold text-emerald-700 sm:inline">
            Backend verified
          </span>
          <div className="grid h-10 w-10 place-items-center rounded-full bg-slate-900 text-sm font-bold text-white">
            SA
          </div>
        </div>
      </div>
    </header>
  );
}