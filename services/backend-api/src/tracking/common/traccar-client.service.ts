import { BadGatewayException, GatewayTimeoutException, Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { TraccarServer } from '../../generated/prisma/client';
import {
  TrackingCredentialCryptoService,
  type TraccarCredentials,
} from './tracking-credential-crypto.service';

export interface TraccarDevice {
  id: number;
  name: string;
  uniqueId: string;
  status?: string;
  disabled?: boolean;
  category?: string;
  attributes?: Record<string, unknown>;
}

export interface TraccarPosition {
  id: number;
  deviceId: number;
  protocol?: string;
  serverTime?: string;
  deviceTime?: string;
  fixTime?: string;
  outdated?: boolean;
  valid?: boolean;
  latitude: number;
  longitude: number;
  altitude?: number;
  speed?: number;
  course?: number;
  address?: string;
  accuracy?: number;
  network?: Record<string, unknown>;
  attributes?: Record<string, unknown>;
}

export interface TraccarEvent {
  id: number;
  type: string;
  eventTime?: string;
  deviceId: number;
  positionId?: number;
  geofenceId?: number;
  maintenanceId?: number;
  attributes?: Record<string, unknown>;
}

export interface TraccarGeofence {
  id: number;
  name: string;
  description?: string;
  area: string;
  calendarId?: number;
  attributes?: Record<string, unknown>;
}

export interface TraccarCommandResult {
  id?: number;
  deviceId?: number;
  type?: string;
  textChannel?: boolean;
  attributes?: Record<string, unknown>;
}

export interface TraccarServerHealth {
  id?: number;
  version?: string;
  registration?: boolean;
  readonly?: boolean;
  map?: string;
  bingKey?: string;
  forceSettings?: boolean;
  coordinateFormat?: string;
  limitCommands?: boolean;
  attributes?: Record<string, unknown>;
}

interface RequestOptions {
  method?: 'GET' | 'POST' | 'PUT' | 'DELETE';
  query?: Record<string, string | number | boolean | undefined>;
  body?: unknown;
}

@Injectable()
export class TraccarClientService {
  private readonly timeoutMs: number;

  constructor(
    private readonly credentialCrypto: TrackingCredentialCryptoService,
    configService: ConfigService,
  ) {
    this.timeoutMs = configService.get<number>('TRACKING_HTTP_TIMEOUT_MS', 10000);
  }

  health(server: TraccarServer): Promise<TraccarServerHealth> {
    return this.request<TraccarServerHealth>(server, '/api/server');
  }

  findDeviceByUniqueId(server: TraccarServer, uniqueId: string): Promise<TraccarDevice[]> {
    return this.request<TraccarDevice[]>(server, '/api/devices', {
      query: {
        uniqueId,
      },
    });
  }

  createDevice(
    server: TraccarServer,
    input: {
      name: string;
      uniqueId: string;
      disabled?: boolean;
      category?: string;
      attributes?: Record<string, unknown>;
    },
  ): Promise<TraccarDevice> {
    return this.request<TraccarDevice>(server, '/api/devices', {
      method: 'POST',
      body: input,
    });
  }

  updateDevice(
    server: TraccarServer,
    traccarDeviceId: bigint,
    input: {
      id: number;
      name: string;
      uniqueId: string;
      disabled?: boolean;
      category?: string;
      attributes?: Record<string, unknown>;
    },
  ): Promise<TraccarDevice> {
    return this.request<TraccarDevice>(server, `/api/devices/${this.safeNumber(traccarDeviceId)}`, {
      method: 'PUT',
      body: input,
    });
  }

  latestPositions(server: TraccarServer, traccarDeviceId: bigint): Promise<TraccarPosition[]> {
    return this.request<TraccarPosition[]>(server, '/api/positions', {
      query: {
        deviceId: this.safeNumber(traccarDeviceId),
      },
    });
  }

  positionHistory(
    server: TraccarServer,
    traccarDeviceId: bigint,
    from: Date,
    to: Date,
  ): Promise<TraccarPosition[]> {
    return this.request<TraccarPosition[]>(server, '/api/positions', {
      query: {
        deviceId: this.safeNumber(traccarDeviceId),
        from: from.toISOString(),
        to: to.toISOString(),
      },
    });
  }

  eventHistory(
    server: TraccarServer,
    traccarDeviceId: bigint,
    from: Date,
    to: Date,
  ): Promise<TraccarEvent[]> {
    return this.request<TraccarEvent[]>(server, '/api/events', {
      query: {
        deviceId: this.safeNumber(traccarDeviceId),
        from: from.toISOString(),
        to: to.toISOString(),
      },
    });
  }

  createGeofence(
    server: TraccarServer,
    input: {
      name: string;
      description?: string;
      area: string;
      attributes?: Record<string, unknown>;
    },
  ): Promise<TraccarGeofence> {
    return this.request<TraccarGeofence>(server, '/api/geofences', {
      method: 'POST',
      body: input,
    });
  }

  updateGeofence(
    server: TraccarServer,
    traccarGeofenceId: bigint,
    input: {
      id: number;
      name: string;
      description?: string;
      area: string;
      attributes?: Record<string, unknown>;
    },
  ): Promise<TraccarGeofence> {
    return this.request<TraccarGeofence>(
      server,
      `/api/geofences/${this.safeNumber(traccarGeofenceId)}`,
      {
        method: 'PUT',
        body: input,
      },
    );
  }

  deleteGeofence(server: TraccarServer, traccarGeofenceId: bigint): Promise<void> {
    return this.request<void>(server, `/api/geofences/${this.safeNumber(traccarGeofenceId)}`, {
      method: 'DELETE',
    });
  }

  linkDeviceGeofence(
    server: TraccarServer,
    traccarDeviceId: bigint,
    traccarGeofenceId: bigint,
  ): Promise<void> {
    return this.request<void>(server, '/api/permissions', {
      method: 'POST',
      body: {
        deviceId: this.safeNumber(traccarDeviceId),
        geofenceId: this.safeNumber(traccarGeofenceId),
      },
    });
  }

  unlinkDeviceGeofence(
    server: TraccarServer,
    traccarDeviceId: bigint,
    traccarGeofenceId: bigint,
  ): Promise<void> {
    return this.request<void>(server, '/api/permissions', {
      method: 'DELETE',
      body: {
        deviceId: this.safeNumber(traccarDeviceId),
        geofenceId: this.safeNumber(traccarGeofenceId),
      },
    });
  }

  sendCommand(
    server: TraccarServer,
    traccarDeviceId: bigint,
    input: {
      type: string;
      attributes?: Record<string, unknown>;
    },
  ): Promise<TraccarCommandResult> {
    return this.request<TraccarCommandResult>(server, '/api/commands/send', {
      method: 'POST',
      body: {
        deviceId: this.safeNumber(traccarDeviceId),
        type: input.type,
        attributes: input.attributes ?? {},
      },
    });
  }

  private async request<T>(
    server: TraccarServer,
    path: string,
    options: RequestOptions = {},
  ): Promise<T> {
    const credentials = this.credentialCrypto.decrypt(server.encryptedCredentialReference);
    const url = this.createUrl(server.baseUrl, path, options.query);
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), this.timeoutMs);

    try {
      const response = await fetch(url, {
        method: options.method ?? 'GET',
        headers: this.headers(credentials, options.body !== undefined),
        body: options.body === undefined ? undefined : JSON.stringify(options.body),
        signal: controller.signal,
      });

      if (!response.ok) {
        const body = await response.text();

        throw new BadGatewayException({
          message: 'Traccar request failed.',
          traccarStatus: response.status,
          traccarBody: body.slice(0, 1000),
        });
      }

      if (response.status === 204) {
        return undefined as T;
      }

      const text = await response.text();

      if (!text) {
        return undefined as T;
      }

      return JSON.parse(text) as T;
    } catch (error) {
      if (error instanceof Error && error.name === 'AbortError') {
        throw new GatewayTimeoutException('Traccar request timed out.');
      }

      if (error instanceof BadGatewayException || error instanceof GatewayTimeoutException) {
        throw error;
      }

      throw new BadGatewayException({
        message: 'Could not communicate with Traccar.',
        cause: error instanceof Error ? error.message : 'Unknown Traccar error',
      });
    } finally {
      clearTimeout(timeout);
    }
  }

  private createUrl(
    baseUrl: string,
    path: string,
    query?: Record<string, string | number | boolean | undefined>,
  ): string {
    const url = new URL(path, `${baseUrl.replace(/\/+$/, '')}/`);

    for (const [key, value] of Object.entries(query ?? {})) {
      if (value !== undefined) {
        url.searchParams.set(key, String(value));
      }
    }

    return url.toString();
  }

  private headers(credentials: TraccarCredentials, hasBody: boolean): Record<string, string> {
    const headers: Record<string, string> = {
      Accept: 'application/json',
    };

    if (hasBody) {
      headers['Content-Type'] = 'application/json';
    }

    if (credentials.token) {
      headers.Authorization = `Bearer ${credentials.token}`;
    } else if (credentials.username !== undefined && credentials.password !== undefined) {
      headers.Authorization = `Basic ${Buffer.from(
        `${credentials.username}:${credentials.password}`,
      ).toString('base64')}`;
    }

    return headers;
  }

  private safeNumber(value: bigint): number {
    const number = Number(value);

    if (!Number.isSafeInteger(number)) {
      throw new BadGatewayException(
        'Traccar identifier exceeds the JavaScript safe-integer range.',
      );
    }

    return number;
  }
}
