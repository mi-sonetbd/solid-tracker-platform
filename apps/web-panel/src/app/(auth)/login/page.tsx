"use client";

import {
  Check,
  ChevronDown,
  Eye,
  LockKeyhole,
  UserRound,
} from "lucide-react";
import { LoginVisual } from "@/components/auth/login-visual";
import { SolidTrackerWordmark } from "@/components/brand/solid-tracker-wordmark";

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

          <form className="mx-auto mt-9 w-full max-w-[282px]">
            <label className="st-input-focus flex h-9 items-center rounded-[3px] border border-[#ced7e5] px-3 transition">
              <UserRound className="h-4 w-4 shrink-0 text-[#627694]" />
              <input
                type="text"
                name="username"
                autoComplete="username"
                defaultValue="admin"
                className="min-w-0 flex-1 border-0 bg-transparent px-2 text-[12px] text-[#465c7f] outline-none"
              />
            </label>

            <label className="st-input-focus mt-3 flex h-9 items-center rounded-[3px] border border-[#ced7e5] px-3 transition">
              <LockKeyhole className="h-4 w-4 shrink-0 text-[#627694]" />
              <input
                type="password"
                name="password"
                autoComplete="current-password"
                defaultValue="solidtracker"
                className="min-w-0 flex-1 border-0 bg-transparent px-2 text-[12px] text-[#465c7f] outline-none"
              />
              <Eye className="h-4 w-4 text-[#627694]" />
            </label>

            <div className="mt-3 flex items-center justify-between text-[12px]">
              <label className="flex items-center gap-2 text-[#52698e]">
                <span className="grid h-3.5 w-3.5 place-items-center rounded-[2px] bg-[#4b83f7] text-white">
                  <Check className="h-3 w-3" strokeWidth={3} />
                </span>
                Remember me
              </label>

              <button type="button" className="text-[#52698e]">
                Forgot your password?
              </button>
            </div>

            <button
              type="button"
              className="mt-10 h-9 w-full rounded-[3px] bg-[#397bf3] text-[13px] font-semibold text-white transition hover:bg-[#2766d5]"
            >
              Login
            </button>

            <button
              type="button"
              className="mt-1 block w-full text-right text-[12px] text-[#397bf3]"
            >
              Demo Â»
            </button>
          </form>

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