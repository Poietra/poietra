import { defineConfig } from '@playwright/test';
import effects from './effects.config';
const port = Number(process.env.WRITE_TEST_PORT ?? 5177);
export default defineConfig({
  ...effects, testMatch: ['effects-write.spec.ts', 'effects-svg-profile.spec.ts', 'effects-shape-text.spec.ts'], timeout: 180_000,
  outputDir: process.env.WRITE_RESULTS_DIR ?? '../../test-results/effects-write',
  use: { ...effects.use, baseURL: `http://127.0.0.1:${port}`, trace: 'off' },
  webServer: {
    command: `pnpm exec vite preview --outDir ${process.env.WRITE_BUILD_DIR ?? 'test-results/effects-write-build'} --host 127.0.0.1 --port ${port} --strictPort`,
    cwd: '../..', url: `http://127.0.0.1:${port}/tests/e2e/fixtures/effects-write.html`, reuseExistingServer: process.env.WRITE_REUSE_SERVER === '1', timeout: 60_000,
  },
});
