import type { ReporterDescription } from '@playwright/test';
import { fileURLToPath } from 'node:url';

// Keep successful timings as well as failure evidence. Shards run on separate runners.
export function report(suite: string): ReporterDescription[] {
  return process.env.CI
    ? [['list'], ['json', { outputFile: fileURLToPath(new URL(`../../test-results/reports/${suite}.json`, import.meta.url)) }]]
    : [['list']];
}
