export type BackendRole = {
  code: string;
  scopeType: string;
  scopeId: string;
};

export type BackendAuthContext = {
  userId: string;
  sessionId: string;
  userCode: string;
  fullName: string;
  mobileNumber: string;
  roles: BackendRole[];
  permissions: string[];
  organizationIds: string[];
  customerIds: string[];
};

export type BackendTokenResponse = {
  tokenType: string;
  accessToken: string;
  refreshToken: string;
};

export type WorkspaceKind =
  | "CUSTOMER"
  | "DEALER"
  | "DEALER_MANAGER"
  | "ADMIN"
  | "SUPER_ADMIN"
  | "UNKNOWN";

export type WebSession = {
  authenticated: true;
  user: BackendAuthContext;
  workspace: WorkspaceKind;
  redirectTo: string;
};

export type LoginRequest = {
  mobileNumber: string;
  password: string;
  rememberMe: boolean;
};