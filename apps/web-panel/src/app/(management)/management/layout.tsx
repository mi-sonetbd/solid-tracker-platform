import { ManagementShell } from "@/components/layout/management-shell";
import { requireManagementSession } from "@/lib/auth/server-session";
import { managementScopeLabel } from "@/lib/auth/management-access";
import { workspaceLabel } from "@/lib/auth/workspace";

export default async function ManagementLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  const session = await requireManagementSession();

  return (
    <ManagementShell
      user={{
        fullName: session.user.fullName,
        workspaceLabel: workspaceLabel(session.workspace),
        scopeLabel: managementScopeLabel(session.workspace),
      }}
    >
      {children}
    </ManagementShell>
  );
}