import {
  BadgeCheck,
  LayoutTemplate,
} from "lucide-react";
import { LogoutButton } from "@/components/auth/logout-button";
import { SolidTrackerWordmark } from "@/components/brand/solid-tracker-wordmark";
import { requireAnySession } from "@/lib/auth/server-session";
import { workspaceLabel } from "@/lib/auth/workspace";

export default async function RoleTemplatePendingPage() {
  const session = await requireAnySession();
  const label = workspaceLabel(session.workspace);

  return (
    <main className="grid min-h-screen place-items-center bg-[#f1f4f8] px-5 py-10">
      <section className="w-full max-w-xl rounded-[8px] bg-white p-8 text-center shadow-[0_12px_35px_rgba(41,68,112,0.12)]">
        <div className="flex justify-center">
          <SolidTrackerWordmark href="" compact />
        </div>

        <div className="mx-auto mt-8 grid h-16 w-16 place-items-center rounded-full bg-[#eaf2ff] text-[#357cf4]">
          <LayoutTemplate className="h-8 w-8" />
        </div>

        <div className="mt-6 flex items-center justify-center gap-2 text-[12px] font-semibold text-emerald-700">
          <BadgeCheck className="h-4 w-4" />
          Account authenticated
        </div>

        <h1 className="mt-3 text-2xl font-bold text-[#30486d]">
          {label} workspace template pending
        </h1>

        <p className="mx-auto mt-4 max-w-md text-[13px] leading-6 text-[#71819c]">
          This account will not use the Customer interface. Its
          dedicated Solid Tracker template will be applied after the
          role-specific design is provided.
        </p>

        <div className="mt-6 rounded-[5px] bg-[#f5f8fc] px-4 py-3 text-left text-[12px] leading-6 text-[#52698e]">
          <p>
            <strong>User:</strong> {session.user.fullName}
          </p>
          <p>
            <strong>Mobile:</strong> {session.user.mobileNumber}
          </p>
          <p>
            <strong>Workspace:</strong> {label}
          </p>
        </div>

        <div className="mt-7">
          <LogoutButton />
        </div>
      </section>
    </main>
  );
}