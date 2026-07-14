import { BadGatewayException, GatewayTimeoutException, Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

interface GatewayRequestOptions {
  method?: 'GET' | 'POST';
  headers?: Record<string, string>;
  body?: string;
}

@Injectable()
export class GatewayHttpService {
  private readonly timeoutMs: number;

  constructor(configService: ConfigService) {
    this.timeoutMs = configService.get<number>('PAYMENT_GATEWAY_HTTP_TIMEOUT_MS', 15000);
  }

  async json<T>(url: string, options: GatewayRequestOptions = {}): Promise<T> {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), this.timeoutMs);

    try {
      const response = await fetch(url, {
        method: options.method ?? 'GET',
        headers: options.headers,
        body: options.body,
        signal: controller.signal,
      });

      const text = await response.text();
      let payload: unknown = {};

      if (text.trim()) {
        try {
          payload = JSON.parse(text);
        } catch {
          payload = {
            raw: text,
          };
        }
      }

      if (!response.ok) {
        throw new BadGatewayException(`Gateway HTTP ${response.status}: ${text.slice(0, 500)}`);
      }

      return payload as T;
    } catch (error) {
      if (error instanceof Error && error.name === 'AbortError') {
        throw new GatewayTimeoutException('Payment gateway request timed out.');
      }

      if (error instanceof BadGatewayException || error instanceof GatewayTimeoutException) {
        throw error;
      }

      throw new BadGatewayException(
        error instanceof Error ? error.message : 'Unknown payment gateway error.',
      );
    } finally {
      clearTimeout(timeout);
    }
  }

  form<T>(url: string, fields: Record<string, string>): Promise<T> {
    return this.json<T>(url, {
      method: 'POST',
      headers: {
        'content-type': 'application/x-www-form-urlencoded',
      },
      body: new URLSearchParams(fields).toString(),
    });
  }
}
