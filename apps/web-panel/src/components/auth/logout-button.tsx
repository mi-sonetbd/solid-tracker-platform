"use client";

import { LogOut } from "lucide-react";
import { useRouter } from "next/navigation";
import { useState } from "react";

export function LogoutButton() {
  const router = useRouter();
  const [submitting, setSubmitting] = useState(false);

  async function logout() {
    setSubmitting(true);

    try {
      await fetch("/api/auth/logout", {
        method: "POST",
      });
    } finally {
      router.replace("/login");
      router.refresh();
    }
  }

  return (
    <button
      type="button"
      onClick={logout}
      disabled={submitting}
      className="inline-flex h-9 items-center justify-center gap-2 rounded-[3px] bg-[#357cf4] px-5 text-[12px] font-semibold text-white disabled:opacity-60"
    >
      <LogOut className="h-4 w-4" />
      {submitting ? "Signing out" : "Sign out"}
    </button>
  );
}