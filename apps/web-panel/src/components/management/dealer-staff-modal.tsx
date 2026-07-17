"use client";

import {
  CalendarClock,
  LoaderCircle,
  RefreshCw,
  ShieldCheck,
  UserRoundPlus,
  UsersRound,
  X,
} from "lucide-react";
import {
  useEffect,
  useState,
} from "react";
import type {
  DealerStaffMembership,
  DealerSummary,
  ManagementApiError,
} from "@/lib/management/dealer-types";

type DealerStaffModalProps = {
  dealer: DealerSummary;
  canManageStaff: boolean;
  refreshVersion: number;
  onAddManager: () => void;
  onClose: () => void;
};

function formatDate(value: string | null) {
  if (!value) {
    return "Never";
  }

  const date = new Date(value);

  if (Number.isNaN(date.getTime())) {
    return "-";
  }

  return new Intl.DateTimeFormat("en-GB", {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(date);
}

export function DealerStaffModal({
  dealer,
  canManageStaff,
  refreshVersion,
  onAddManager,
  onClose,
}: DealerStaffModalProps) {
  const [staff, setStaff] = useState<DealerStaffMembership[]>(
    [],
  );
  const [loading, setLoading] = useState(true);
  const [localRefreshVersion, setLocalRefreshVersion] =
    useState(0);
  const [error, setError] = useState("");

  useEffect(() => {
    const controller = new AbortController();

    void fetch(
      `/api/management/dealers/${dealer.id}/staff`,
      {
        cache: "no-store",
        signal: controller.signal,
      },
    )
      .then(async (response) => {
        const result = (await response.json()) as
          | DealerStaffMembership[]
          | ManagementApiError;

        if (!response.ok) {
          throw new Error(
            "message" in result
              ? result.message
              : "Dealer staff loading failed.",
          );
        }

        if (controller.signal.aborted) {
          return;
        }

        setStaff(result as DealerStaffMembership[]);
        setError("");
      })
      .catch((reason: unknown) => {
        if (
          controller.signal.aborted ||
          (reason instanceof DOMException &&
            reason.name === "AbortError")
        ) {
          return;
        }

        setError(
          reason instanceof Error
            ? reason.message
            : "The Dealer staff directory is unavailable.",
        );
      })
      .finally(() => {
        if (!controller.signal.aborted) {
          setLoading(false);
        }
      });

    return () => {
      controller.abort();
    };
  }, [dealer.id, localRefreshVersion, refreshVersion]);

  function refresh() {
    setError("");
    setLoading(true);
    setLocalRefreshVersion((value) => value + 1);
  }

  return (
    <div
      className="fixed inset-0 z-[2200] grid place-items-center bg-[#17345f]/45 p-5"
      role="presentation"
      onMouseDown={(event) => {
        if (event.target === event.currentTarget) {
          onClose();
        }
      }}
    >
      <section
        role="dialog"
        aria-modal="true"
        aria-labelledby="dealer-staff-title"
        className="flex max-h-[90vh] w-full max-w-[980px] flex-col overflow-hidden rounded-[8px] bg-white shadow-[0_28px_80px_rgba(18,44,86,0.3)]"
      >
        <header className="flex min-h-16 shrink-0 items-center justify-between gap-4 border-b border-[#dfe6ef] px-6 py-3">
          <div className="flex min-w-0 items-center gap-3">
            <span className="grid h-10 w-10 shrink-0 place-items-center rounded-full bg-[#eaf2ff] text-[#357cf4]">
              <UsersRound className="h-5 w-5" />
            </span>

            <div className="min-w-0">
              <h2
                id="dealer-staff-title"
                className="truncate text-[17px] font-semibold text-[#344b72]"
              >
                {dealer.name} Staff
              </h2>
              <p className="mt-0.5 truncate text-[11px] text-[#7c8ba5]">
                {dealer.dealerProfile.dealerCode} Â· Dealer-scoped memberships and roles
              </p>
            </div>
          </div>

          <div className="flex shrink-0 items-center gap-2">
            <button
              type="button"
              disabled={loading}
              onClick={refresh}
              className="grid h-9 w-9 place-items-center rounded-[3px] border border-[#cfd8e7] text-[#52698e] disabled:opacity-50"
              aria-label="Refresh Dealer staff"
            >
              <RefreshCw
                className={[
                  "h-4 w-4",
                  loading ? "animate-spin" : "",
                ].join(" ")}
              />
            </button>

            <button
              type="button"
              disabled={!canManageStaff}
              onClick={onAddManager}
              className="flex h-9 items-center gap-2 rounded-[3px] bg-[#357cf4] px-4 text-[11px] font-semibold text-white disabled:bg-[#b8c7dc]"
            >
              <UserRoundPlus className="h-4 w-4" />
              Add Manager
            </button>

            <button
              type="button"
              onClick={onClose}
              aria-label="Close Dealer staff dialog"
              className="grid h-9 w-9 place-items-center text-[#71819c]"
            >
              <X className="h-5 w-5" />
            </button>
          </div>
        </header>

        <div className="st-scrollbar min-h-[300px] flex-1 overflow-auto p-5">
          {error ? (
            <div
              role="alert"
              className="mb-4 rounded-[4px] border border-red-200 bg-red-50 px-4 py-3 text-[12px] text-red-700"
            >
              {error}
            </div>
          ) : null}

          {loading ? (
            <div className="flex min-h-[280px] items-center justify-center gap-2 text-[12px] text-[#71819c]">
              <LoaderCircle className="h-5 w-5 animate-spin text-[#357cf4]" />
              Loading Dealer staff
            </div>
          ) : staff.length === 0 ? (
            <div className="grid min-h-[280px] place-items-center text-center">
              <div>
                <UsersRound className="mx-auto h-10 w-10 text-[#b5c2d5]" />
                <p className="mt-3 text-[12px] font-semibold text-[#52698e]">
                  No staff provisioned
                </p>
                <p className="mt-1 text-[10px] text-[#8b9ab4]">
                  Create the first Dealer Manager for this Dealer.
                </p>
              </div>
            </div>
          ) : (
            <div className="overflow-hidden rounded-[5px] border border-[#dfe6ef]">
              <table className="w-full min-w-[820px] text-left text-[11px]">
                <thead className="bg-[#edf2f8] text-[#405779]">
                  <tr>
                    {[
                      "User",
                      "Mobile",
                      "Role",
                      "Membership",
                      "Account",
                      "Last login",
                    ].map((heading) => (
                      <th
                        key={heading}
                        className="px-4 py-3 font-semibold"
                      >
                        {heading}
                      </th>
                    ))}
                  </tr>
                </thead>

                <tbody>
                  {staff.map((membership) => (
                    <tr
                      key={membership.id}
                      className="border-t border-[#e2e8f1] text-[#52698e]"
                    >
                      <td className="px-4 py-4">
                        <p className="font-semibold text-[#405779]">
                          {membership.user.fullName}
                        </p>
                        <p className="mt-1 text-[9px] text-[#8b9ab4]">
                          {membership.user.userCode}
                        </p>
                      </td>

                      <td className="px-4 py-4">
                        <p>{membership.user.mobileNumber}</p>
                        <p className="mt-1 text-[9px] text-[#8b9ab4]">
                          {membership.user.email || "-"}
                        </p>
                      </td>

                      <td className="px-4 py-4">
                        <div className="space-y-1">
                          {membership.roleAssignments.map(
                            (assignment) => (
                              <span
                                key={assignment.id}
                                className="flex w-fit items-center gap-1 rounded-full bg-[#eaf2ff] px-2 py-1 text-[9px] font-semibold text-[#357cf4]"
                              >
                                <ShieldCheck className="h-3 w-3" />
                                {assignment.role.code}
                              </span>
                            ),
                          )}
                        </div>
                      </td>

                      <td className="px-4 py-4">
                        <span className="rounded-full bg-slate-100 px-2 py-1 text-[9px] font-semibold text-slate-600">
                          {membership.status}
                        </span>
                      </td>

                      <td className="px-4 py-4">
                        <span className="rounded-full bg-emerald-50 px-2 py-1 text-[9px] font-semibold text-emerald-700">
                          {membership.user.status}
                        </span>
                      </td>

                      <td className="px-4 py-4">
                        <span className="flex items-center gap-1">
                          <CalendarClock className="h-3.5 w-3.5" />
                          {formatDate(
                            membership.user.lastLoginAt,
                          )}
                        </span>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>
      </section>
    </div>
  );
}