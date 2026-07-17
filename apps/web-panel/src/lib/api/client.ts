import { env } from "@/lib/env";

export class ApiError extends Error {
  constructor(
    message: string,
    public readonly status: number,
    public readonly payload?: unknown,
  ) {
    super(message);
    this.name = "ApiError";
  }
}

type ApiRequestOptions = Omit<RequestInit, "body"> & {
  body?: unknown;
  accessToken?: string;
};

export async function apiRequest<T>(
  path: string,
  options: ApiRequestOptions = {},
): Promise<T> {
  const { accessToken, body, headers, ...requestOptions } = options;

  const response = await fetch(
    new URL(path.replace(/^\//, ""), `${env.apiBaseUrl}/`),
    {
      ...requestOptions,
      body: body === undefined ? undefined : JSON.stringify(body),
      headers: {
        Accept: "application/json",
        ...(body === undefined ? {} : { "Content-Type": "application/json" }),
        ...(accessToken
          ? { Authorization: `Bearer ${accessToken}` }
          : {}),
        ...headers,
      },
    },
  );

  const contentType = response.headers.get("content-type") ?? "";
  const payload = contentType.includes("application/json")
    ? await response.json()
    : await response.text();

  if (!response.ok) {
    throw new ApiError(
      `Solid Tracker API request failed with status ${response.status}.`,
      response.status,
      payload,
    );
  }

  return payload as T;
}