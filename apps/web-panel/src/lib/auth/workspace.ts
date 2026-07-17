import type {
  BackendAuthContext,
  WorkspaceKind,
} from "@/lib/auth/auth-types";

const managementWorkspaces: WorkspaceKind[] = [
  "SUPER_ADMIN",
  "ADMIN",
  "DEALER_MANAGER",
  "DEALER",
];

function normalizedRoleCodes(context: BackendAuthContext) {
  return context.roles.map((role) =>
    role.code.trim().toUpperCase().replace(/[\s-]+/g, "_"),
  );
}

export function resolveWorkspace(
  context: BackendAuthContext,
): WorkspaceKind {
  const roleCodes = normalizedRoleCodes(context);

  if (
    roleCodes.some(
      (code) =>
        code.includes("SUPER_ADMIN") ||
        code.includes("PLATFORM_OWNER"),
    )
  ) {
    return "SUPER_ADMIN";
  }

  if (
    roleCodes.some(
      (code) =>
        code === "ADMIN" ||
        code.includes("PLATFORM_ADMIN") ||
        code.includes("SYSTEM_ADMIN"),
    )
  ) {
    return "ADMIN";
  }

  if (
    roleCodes.some(
      (code) =>
        code.includes("DEALER_MANAGER") ||
        code.includes("DEALER_ADMIN"),
    )
  ) {
    return "DEALER_MANAGER";
  }

  if (roleCodes.some((code) => code.includes("DEALER"))) {
    return "DEALER";
  }

  if (
    context.customerIds.length > 0 ||
    roleCodes.some((code) => code.includes("CUSTOMER"))
  ) {
    return "CUSTOMER";
  }

  return "UNKNOWN";
}

export function isManagementWorkspace(
  workspace: WorkspaceKind,
) {
  return managementWorkspaces.includes(workspace);
}

export function workspaceRedirect(workspace: WorkspaceKind) {
  if (workspace === "CUSTOMER") {
    return "/monitor";
  }

  if (isManagementWorkspace(workspace)) {
    return "/management/monitor";
  }

  return `/role-template-pending?workspace=${encodeURIComponent(
    workspace,
  )}`;
}

export function workspaceLabel(workspace: WorkspaceKind) {
  return workspace
    .split("_")
    .map(
      (part) =>
        part.charAt(0) + part.slice(1).toLowerCase(),
    )
    .join(" ");
}