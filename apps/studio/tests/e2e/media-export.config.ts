import { defineConfig } from '@playwright/test';
const baseURL = process.env.POIETRA_TEST_URL ?? 'http://127.0.0.1:5173';
export default defineConfig({ testDir: '.', testMatch: 'media-export.spec.ts', timeout: 120000, workers: 1,
  outputDir: '../../test-results/media-export', use: { baseURL, headless: true, viewport: { width: 1280, height: 800 } },
  webServer: process.env.POIETRA_TEST_URL ? undefined : { command: 'pnpm dev', url: `${baseURL}/api/health`, reuseExistingServer: !process.env.CI },
});
