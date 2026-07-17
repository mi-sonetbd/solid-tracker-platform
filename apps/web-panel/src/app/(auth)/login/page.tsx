import { ChevronDown } from "lucide-react";
import { Suspense } from "react";
import { LoginForm } from "@/components/auth/login-form";
import { LoginVisual } from "@/components/auth/login-visual";
import { SolidTrackerWordmark } from "@/components/brand/solid-tracker-wordmark";

function LoginFormFallback() {
  return (
    <div
      aria-hidden="true"
      className="mx-auto mt-9 w-full max-w-[282px] animate-pulse"
    >
      <div className="h-9 rounded-[3px] bg-[#edf1f7]" />
      <div className="mt-3 h-9 rounded-[3px] bg-[#edf1f7]" />

      <div className="mt-3 flex items-center justify-between">
        <div className="h-3.5 w-24 rounded bg-[#edf1f7]" />
        <div className="h-3.5 w-28 rounded bg-[#edf1f7]" />
      </div>

      <div className="mt-10 h-9 rounded-[3px] bg-[#dbe7fb]" />
    </div>
  );
}

export default function LoginPage() {
  return (
    <main className="st-login-background relative grid min-h-screen place-items-center overflow-hidden px-5 py-8">
      <div className="absolute left-[8%] top-[5%] h-56 w-56 rounded-full bg-cyan-200/10 blur-3xl" />
      <div className="absolute bottom-[6%] right-[9%] h-72 w-72 rounded-full bg-indigo-200/10 blur-3xl" />

      <section className="relative z-10 grid w-full max-w-[920px] overflow-hidden rounded-[14px] bg-white shadow-[0_28px_70px_rgba(22,61,151,0.3)] md:grid-cols-2">
        <LoginVisual />

        <div className="relative flex min-h-[610px] flex-col bg-white px-10 pb-7 pt-4 md:px-[76px]">
          <button
            type="button"
            className="ml-auto flex h-8 min-w-[102px] items-center justify-between rounded-[3px] border border-[#ced7e5] px-3 text-[12px] text-[#617391]"
          >
            English
            <ChevronDown className="h-3.5 w-3.5" />
          </button>

          <div className="mt-[82px] flex justify-center">
            <SolidTrackerWordmark href="" />
          </div>

          <Suspense fallback={<LoginFormFallback />}>
            <LoginForm />
          </Suspense>

          <footer className="mt-auto flex justify-center gap-3 text-[11px] text-[#7c8ba5]">
            <button type="button">Terms of Service</button>
            <span>|</span>
            <button type="button">Privacy Policy</button>
          </footer>
        </div>
      </section>
    </main>
  );
}