import "server-only";

function readPositiveInteger(name: string, fallback: number) {
  const value = Number(process.env[name] ?? fallback);

  if (!Number.isInteger(value) || value <= 0) {
    throw new Error(`${name} must be a positive integer.`);
  }

  return value;
}

const rawBaseUrl =
  process.env.SOLID_TRACKER_API_BASE_URL ??
  "http://localhost:3000/api/v1";

export const authConfig = {
  apiBaseUrl: rawBaseUrl.replace(/\/+$/, ""),
  accessCookieMaxAge: readPositiveInteger(
    "SOLID_TRACKER_ACCESS_COOKIE_MAX_AGE",
    900,
  ),
  refreshCookieMaxAge: readPositiveInteger(
    "SOLID_TRACKER_REFRESH_COOKIE_MAX_AGE",
    2_592_000,
  ),
  appVersion:
    process.env.SOLID_TRACKER_WEB_APP_VERSION ?? "0.1.0",
} as const;