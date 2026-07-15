export const env = {
  appName: process.env.NEXT_PUBLIC_APP_NAME ?? "Solid Tracker",
  apiBaseUrl:
    process.env.NEXT_PUBLIC_API_BASE_URL ?? "http://localhost:3000",
} as const;