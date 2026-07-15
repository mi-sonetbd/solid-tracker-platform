import type { PanelRole } from "@/config/navigation";

export type AuthenticatedUser = {
  id: string;
  displayName: string;
  mobileNumber: string;
  role: PanelRole;
};

export type LoginRequest = {
  mobileNumber: string;
  password: string;
};

export type LoginResponse = {
  accessToken: string;
  refreshToken: string;
  user: AuthenticatedUser;
};