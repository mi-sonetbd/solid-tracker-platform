import type { Request } from 'express';

export interface AuthenticatedRole {
  code: string;
  scopeType: string;
  scopeId: string;
}

export interface AuthContext {
  userId: string;
  sessionId: string;
  userCode: string;
  fullName: string;
  mobileNumber: string;
  roles: AuthenticatedRole[];
  permissions: string[];
  organizationIds: string[];
  customerIds: string[];
}

export interface AuthenticatedRequest extends Request {
  auth?: AuthContext;
}
