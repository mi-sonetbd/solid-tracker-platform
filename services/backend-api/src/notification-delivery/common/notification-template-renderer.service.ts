import { BadRequestException, Injectable } from '@nestjs/common';

@Injectable()
export class NotificationTemplateRendererService {
  render(template: string, variables: Record<string, unknown>): string {
    return template.replace(/\{\{\s*([a-zA-Z0-9_.-]+)\s*\}\}/g, (_match, path: string) => {
      const value = this.resolvePath(variables, path);

      if (value === undefined || value === null) {
        throw new BadRequestException(`Template variable "${path}" is required.`);
      }

      return typeof value === 'object' ? JSON.stringify(value) : String(value);
    });
  }

  referencedVariables(template: string): string[] {
    const values = new Set<string>();

    for (const match of template.matchAll(/\{\{\s*([a-zA-Z0-9_.-]+)\s*\}\}/g)) {
      values.add(match[1]);
    }

    return Array.from(values).sort();
  }

  private resolvePath(variables: Record<string, unknown>, path: string): unknown {
    return path.split('.').reduce<unknown>((current, segment) => {
      if (current === null || typeof current !== 'object' || Array.isArray(current)) {
        return undefined;
      }

      return (current as Record<string, unknown>)[segment];
    }, variables);
  }
}
