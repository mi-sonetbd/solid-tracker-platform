"use client";

import {
  Check,
  ChevronsRight,
  Eye,
  EyeOff,
  LoaderCircle,
  LockKeyhole,
  UserRound,
} from "lucide-react";
import { useRouter, useSearchParams } from "next/navigation";
import {
  FormEvent,
  useEffect,
  useState,
} from "react";

type LoginResult = {
  redirectTo?: string;
  message?: string;
};

export function LoginForm() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const [mobileNumber, setMobileNumber] = useState("");
  const [password, setPassword] = useState("");
  const [rememberMe, setRememberMe] = useState(true);
  const [showPassword, setShowPassword] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState("");

  useEffect(() => {
    let active = true;

    async function restoreSession() {
      const response = await fetch("/api/auth/session", {
        cache: "no-store",
      });

      if (!active || !response.ok) {
        return;
      }

      const result = (await response.json()) as LoginResult;

      if (result.redirectTo) {
        router.replace(result.redirectTo);
      }
    }

    void restoreSession();

    return () => {
      active = false;
    };
  }, [router]);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError("");
    setSubmitting(true);

    try {
      const response = await fetch("/api/auth/login", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          mobileNumber,
          password,
          rememberMe,
        }),
      });

      const result = (await response.json()) as LoginResult;

      if (!response.ok) {
        setError(result.message ?? "Login failed.");
        return;
      }

      const requestedReturnTo = searchParams.get("returnTo");
      const redirectTo =
        result.redirectTo === "/monitor" &&
        requestedReturnTo?.startsWith("/") &&
        !requestedReturnTo.startsWith("//")
          ? requestedReturnTo
          : result.redirectTo ?? "/monitor";

      router.replace(redirectTo);
      router.refresh();
    } catch {
      setError(
        "The web panel could not reach the authentication service.",
      );
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <form
      className="mx-auto mt-9 w-full max-w-[282px]"
      onSubmit={submit}
    >
      {error ? (
        <div
          role="alert"
          className="mb-3 rounded-[3px] border border-red-200 bg-red-50 px-3 py-2 text-[11px] leading-5 text-red-700"
        >
          {error}
        </div>
      ) : null}

      <label className="st-input-focus flex h-9 items-center rounded-[3px] border border-[#ced7e5] px-3 transition">
        <UserRound className="h-4 w-4 shrink-0 text-[#627694]" />
        <input
          type="tel"
          name="mobileNumber"
          autoComplete="tel"
          value={mobileNumber}
          onChange={(event) => setMobileNumber(event.target.value)}
          placeholder="+8801XXXXXXXXX"
          className="min-w-0 flex-1 border-0 bg-transparent px-2 text-[12px] text-[#465c7f] outline-none placeholder:text-[#9aa8bd]"
          required
        />
      </label>

      <label className="st-input-focus mt-3 flex h-9 items-center rounded-[3px] border border-[#ced7e5] px-3 transition">
        <LockKeyhole className="h-4 w-4 shrink-0 text-[#627694]" />
        <input
          type={showPassword ? "text" : "password"}
          name="password"
          autoComplete="current-password"
          value={password}
          onChange={(event) => setPassword(event.target.value)}
          placeholder="Password"
          className="min-w-0 flex-1 border-0 bg-transparent px-2 text-[12px] text-[#465c7f] outline-none placeholder:text-[#9aa8bd]"
          required
        />
        <button
          type="button"
          aria-label={
            showPassword ? "Hide password" : "Show password"
          }
          onClick={() => setShowPassword((value) => !value)}
          className="text-[#627694]"
        >
          {showPassword ? (
            <EyeOff className="h-4 w-4" />
          ) : (
            <Eye className="h-4 w-4" />
          )}
        </button>
      </label>

      <div className="mt-3 flex items-center justify-between text-[12px]">
        <label className="flex cursor-pointer items-center gap-2 text-[#52698e]">
          <input
            type="checkbox"
            checked={rememberMe}
            onChange={(event) =>
              setRememberMe(event.target.checked)
            }
            className="sr-only"
          />
          <span
            className={[
              "grid h-3.5 w-3.5 place-items-center rounded-[2px] border",
              rememberMe
                ? "border-[#4b83f7] bg-[#4b83f7] text-white"
                : "border-[#b8c4d6] bg-white text-transparent",
            ].join(" ")}
          >
            <Check className="h-3 w-3" strokeWidth={3} />
          </span>
          Remember me
        </label>

        <button type="button" className="text-[#52698e]">
          Forgot your password?
        </button>
      </div>

      <button
        type="submit"
        disabled={submitting}
        className="mt-10 flex h-9 w-full items-center justify-center gap-2 rounded-[3px] bg-[#397bf3] text-[13px] font-semibold text-white transition hover:bg-[#2766d5] disabled:cursor-not-allowed disabled:opacity-70"
      >
        {submitting ? (
          <>
            <LoaderCircle className="h-4 w-4 animate-spin" />
            Signing in
          </>
        ) : (
          "Login"
        )}
      </button>

      <button
        type="button"
        className="mt-1 flex w-full items-center justify-end gap-0.5 text-right text-[12px] text-[#397bf3]"
      >
        <span>Demo</span>
        <ChevronsRight className="h-3.5 w-3.5" />
      </button>
    </form>
  );
}