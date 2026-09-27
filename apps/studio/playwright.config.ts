import { defineConfig } from '@playwright/test';
import { suites } from './tests/e2e/suites.ts';
import { report } from './tests/e2e/report';

const baseURL = process.env.POIETRA_TEST_URL || 'http://127.0.0.1:5173';
export default defineConfig({
  testDir: './tests/e2e',
  testMatch: [...suites.editor, ...suites.components],
  forbidOnly: !!process.env.CI,
  reporter: report('browser'),
  fullyParallel: true,
  workers: 2,
  timeout: 30000,
  use: { baseURL, viewport: { width: 1440, height: 900 }, screenshot: 'only-on-failure', trace: 'retain-on-failure' },
  webServer: process.env.POIETRA_TEST_URL ? undefined : { command: 'pnpm dev', url: `${baseURL}/api/health`, reuseExistingServer: !process.env.CI },
});
