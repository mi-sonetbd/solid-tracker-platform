export type CustomerIndividualProfile = {
  customerId: string;
  fullName: string;
  dateOfBirth: string | null;
  emergencyContactName: string | null;
  emergencyContactMobile: string | null;
};

export type CustomerOrganizationProfile = {
  customerId: string;
  legalName: string;
  displayName: string;
  registrationNumber: string | null;
  taxReference: string | null;
  contactPersonName: string | null;
  contactMobile: string | null;
  contactEmail: string | null;
  operationalAddress: unknown;
};

export type CustomerManagingDealer = {
  id: string;
  code: string;
  name: string;
};

export type CustomerSummary = {
  id: string;
  customerCode: string;
  customerType: "INDIVIDUAL" | "ORGANIZATION";
  status: string;
  managingDealerId: string | null;
  customerGroupId: string | null;
  acquisitionSource: string;
  primaryMobile: string | null;
  primaryEmail: string | null;
  billingAddress: unknown;
  createdAt: string;
  updatedAt: string;
  individualProfile: CustomerIndividualProfile | null;
  organizationProfile: CustomerOrganizationProfile | null;
  managingDealer: CustomerManagingDealer | null;
  customerGroup: {
    id: string;
    code: string;
    name: string;
  } | null;
  _count?: {
    memberships: number;
    vehicles: number;
    billingSubscriptions: number;
  };
};

export type CustomerListResponse = {
  items: CustomerSummary[];
  page: number;
  pageSize: number;
  total: number;
  totalPages: number;
};

export type CreateIndividualCustomerInput = {
  fullName: string;
  primaryMobile: string;
  primaryEmail?: string;
  dateOfBirth?: string;
  emergencyContactName?: string;
  emergencyContactMobile?: string;
  managingDealerId?: string;
};

export type CreateOrganizationCustomerInput = {
  legalName: string;
  displayName: string;
  primaryMobile: string;
  primaryEmail?: string;
  registrationNumber?: string;
  taxReference?: string;
  contactPersonName?: string;
  contactMobile?: string;
  contactEmail?: string;
  managingDealerId?: string;
};

export type CreateCustomerOwnerInput = {
  fullName: string;
  mobileNumber: string;
  email?: string;
  password?: string;
  roleCode: "CUSTOMER_OWNER";
  isPrimary: true;
};

export type CustomerMemberUser = {
  id: string;
  userCode: string;
  fullName: string;
  mobileNumber: string;
  email: string | null;
  status: string;
  lastLoginAt: string | null;
};

export type CustomerMember = {
  id: string;
  customerId: string;
  userId: string;
  status: string;
  isPrimary: boolean;
  invitedByUserId: string | null;
  joinedAt: string | null;
  endedAt: string | null;
  createdAt: string;
  updatedAt: string;
  user: CustomerMemberUser;
};

export type ProvisionedCustomerMember = {
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
    customerId: string;
    userId: string;
    status: string;
    isPrimary: boolean;
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