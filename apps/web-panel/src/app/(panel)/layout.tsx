import { CustomerShell } from "@/components/layout/customer-shell";
import { requireCustomerSession } from "@/lib/auth/server-session";
import { workspaceLabel } from "@/lib/auth/workspace";

export default async function PanelLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  const session = await requireCustomerSession();

  return (
    <CustomerShell
      user={{
        fullName: session.user.fullName,
        workspaceLabel: workspaceLabel(session.workspace),
      }}
    >
      {children}
    </CustomerShell>
  );
}