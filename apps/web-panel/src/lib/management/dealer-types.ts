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

export type ManagementApiError = {
  message: string;
};