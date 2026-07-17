import type { WorkspaceKind } from "@/lib/auth/auth-types";

export function canManageDealers(workspace: WorkspaceKind) {
  return workspace === "SUPER_ADMIN" || workspace === "ADMIN";
}

export function canManageCustomers(workspace: WorkspaceKind) {
  return (
    workspace === "SUPER_ADMIN" ||
    workspace === "ADMIN" ||
    workspace === "DEALER_MANAGER" ||
    workspace === "DEALER"
  );
}

export function canTransferDevices(workspace: WorkspaceKind) {
  return canManageCustomers(workspace);
}

export function managementScopeLabel(
  workspace: WorkspaceKind,
) {
  if (workspace === "SUPER_ADMIN") {
    return "Platform Administration";
  }

  if (workspace === "ADMIN") {
    return "Administration";
  }

  if (workspace === "DEALER_MANAGER") {
    return "Dealer Management";
  }

  return "Dealer Workspace";
}