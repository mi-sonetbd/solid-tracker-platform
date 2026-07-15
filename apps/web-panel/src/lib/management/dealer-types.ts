export type DealerProfile = {
  id: string;
  dealerCode: string;
  tradeLicenseNumber: string | null;
  taxIdentificationNumber: string | null;
  contactMobile: string | null;
  contactEmail: string | null;
  commissionEnabled: boolean;
};

export type DealerZone = {
  id: string;
  code: string;
  name: string;
};

export type DealerSummary = {
  id: string;
  code: string;
  type: string;
  name: string;
  legalName: string | null;
  status: string;
  zoneId: string | null;
  zone: DealerZone | null;
  dealerProfile: DealerProfile;
  createdAt: string;
  updatedAt: string;
  _count?: {
    memberships: number;
    customerGroups: number;
    managedCustomers: number;
  };
};

export type DealerListResponse = {
  items: DealerSummary[];
  page: number;
  pageSize: number;
  total: number;
  totalPages: number;
};

export type CreateDealerInput = {
  name: string;
  legalName?: string;
  tradeLicenseNumber?: string;
  taxIdentificationNumber?: string;
  contactMobile?: string;
  contactEmail?: string;
  commissionEnabled: boolean;
};

export type DealerStaffRole = {
  id: string;
  code: string;
  name: string;
};

export type DealerStaffRoleAssignment = {
  id: string;
  status: string;
  scopeType: string;
  scopeId: string;
  effectiveFrom: string;
  effectiveUntil: string | null;
  role: DealerStaffRole;
};

export type DealerStaffUser = {
  id: string;
  userCode: string;
  fullName: string;
  mobileNumber: string;
  email: string | null;
  status: string;
  lastLoginAt: string | null;
};

export type DealerStaffMembership = {
  id: string;
  organizationId: string;
  userId: string;
  membershipType: string;
  status: string;
  isPrimary: boolean;
  joinedAt: string | null;
  endedAt: string | null;
  createdAt: string;
  updatedAt: string;
  user: DealerStaffUser;
  roleAssignments: DealerStaffRoleAssignment[];
};

export type CreateDealerManagerInput = {
  fullName: string;
  mobileNumber: string;
  email?: string;
  password?: string;
  roleCode: "DEALER_MANAGER";
};

export type ProvisionedDealerStaff = {
  user: {
    id: string;
    userCode: string;
    fullName: string;
    mobileNumber: string;
    email: string | null;
    status: string;
  };
  membership: {
    id: string;
    organizationId: string;
    userId: string;
    membershipType: string;
    status: string;
    joinedAt: string | null;
  };
  roleAssignment: {
    id: string;
    userId: string;
    roleId: string;
    scopeType: string;
    scopeId: string;
    status: string;
  };
};

export type ManagementApiError = {
  message: string;
};

export type ManagementBackendResult<T> =
  | {
      ok: true;
      status: number;
      data: T;
    }
  | {
      ok: false;
      status: number;
      message: string;
      details?: unknown;
    };