import type { Prisma } from '../../generated/prisma/client';

export function toInputJson(value: unknown): Prisma.InputJsonValue | undefined {
  if (value === undefined) {
    return undefined;
  }

  return JSON.parse(
    JSON.stringify(value, (_key, currentValue) =>
      typeof currentValue === 'bigint' ? currentValue.toString() : currentValue,
    ),
  ) as Prisma.InputJsonValue;
}

export function jsonSafe<T>(value: T): unknown {
  return JSON.parse(
    JSON.stringify(value, (_key, currentValue) =>
      typeof currentValue === 'bigint' ? currentValue.toString() : currentValue,
    ),
  ) as unknown;
}
