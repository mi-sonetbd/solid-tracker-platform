import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "Login",
};

export default function LoginPage() {
  return (
    <main className="grid min-h-screen place-items-center bg-slate-950 px-5 py-10">
      <div className="w-full max-w-md rounded-3xl bg-white p-7 shadow-2xl md:p-9">
        <Link href="/" className="inline-flex items-center gap-3">
          <span className="grid h-11 w-11 place-items-center rounded-2xl bg-teal-500 font-black text-slate-950">
            ST
          </span>
          <span>
            <span className="block text-lg font-black tracking-tight text-slate-950">
              Solid Tracker
            </span>
            <span className="block text-xs text-slate-500">
              Secure operations panel
            </span>
          </span>
        </Link>

        <div className="mt-8">
          <p className="text-xs font-bold uppercase tracking-[0.16em] text-teal-700">
            Account access
          </p>
          <h1 className="mt-2 text-3xl font-black tracking-tight text-slate-950">
            Sign in
          </h1>
          <p className="mt-2 text-sm leading-6 text-slate-500">
            The interface is ready. Backend authentication integration is the
            next controlled development stage.
          </p>
        </div>

        <form className="mt-7 space-y-5">
          <label className="block">
            <span className="text-sm font-semibold text-slate-700">
              Mobile number
            </span>
            <input
              type="tel"
              name="mobileNumber"
              autoComplete="tel"
              placeholder="01XXXXXXXXX"
              className="mt-2 w-full rounded-xl border border-slate-300 px-4 py-3 outline-none transition focus:border-teal-600 focus:ring-4 focus:ring-teal-100"
            />
          </label>

          <label className="block">
            <span className="text-sm font-semibold text-slate-700">
              Password
            </span>
            <input
              type="password"
              name="password"
              autoComplete="current-password"
              placeholder="Enter your password"
              className="mt-2 w-full rounded-xl border border-slate-300 px-4 py-3 outline-none transition focus:border-teal-600 focus:ring-4 focus:ring-teal-100"
            />
          </label>

          <button
            type="button"
            className="w-full rounded-xl bg-slate-950 px-5 py-3.5 text-sm font-bold text-white transition hover:bg-slate-800"
          >
            Authentication integration pending
          </button>
        </form>
      </div>
    </main>
  );
}