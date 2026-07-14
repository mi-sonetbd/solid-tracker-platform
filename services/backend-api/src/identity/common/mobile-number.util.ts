import { BadRequestException } from '@nestjs/common';

export function normalizeMobileNumber(value: string): string {
  const compact = value.trim().replace(/[\s()-]/g, '');

  let normalized = compact;

  if (normalized.startsWith('00')) {
    normalized = `+${normalized.slice(2)}`;
  } else if (/^01\d{9}$/.test(normalized)) {
    normalized = `+88${normalized}`;
  } else if (/^8801\d{9}$/.test(normalized)) {
    normalized = `+${normalized}`;
  }

  if (!/^\+\d{8,15}$/.test(normalized)) {
    throw new BadRequestException('Mobile number format is invalid.');
  }

  return normalized;
}
