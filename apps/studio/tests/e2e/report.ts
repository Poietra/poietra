import type { ReporterDescription } from '@playwright/test';

// Keep successful timings as well as failure evidence. Shards run on separate runners.
export function report(suite: string): ReporterDescription[] {
  return process.env.CI
    ? [['list'], ['json', { outputFile: `test-results/reports/${suite}.json` }]]
    : [['list']];
}
