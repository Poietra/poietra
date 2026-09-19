import { defineConfig } from '@playwright/test';
import base from '../../playwright.config';

const baseURL = process.env.POIETRA_TEST_URL || 'http://127.0.0.1:5417';
export default defineConfig({ ...base, webServer: undefined }, {
  testDir: '.',
  testMatch: ['dogfood-landing.spec.ts', 'dogfood-landing-i18n.spec.ts', 'dogfood-home-seo.spec.ts'],
  metadata: { production: true },
  use: { baseURL },
  webServer: process.env.POIETRA_TEST_URL ? undefined : {
    command: 'pnpm start', url: `${baseURL}/api/health`,
    env: { PORT: '5417', POIETRA_DATA_DIR: '.data-ci-site' },
    reuseExistingServer: !process.env.CI,
  },
});
