import { defineConfig } from '@playwright/test';
import effects from './effects.config';
const port = process.env.GLOW_TEST_PORT ?? '5189';
const baseURL = `http://127.0.0.1:${port}`;
export default defineConfig({ ...effects, testMatch: ['glow-initialization.spec.ts', 'glow-buffer.spec.ts'], outputDir: process.env.GLOW_RESULTS_DIR ?? '../../test-results/glow-initialization',
  use: { ...effects.use, baseURL, trace: 'off' },
  webServer: { command: `pnpm exec vite preview --outDir ${process.env.GLOW_BUILD_DIR ?? 'test-results/glow-initialization-build'} --host 127.0.0.1 --port ${port} --strictPort`, cwd: '../..', url: `${baseURL}/tests/e2e/fixtures/glow-initialization.html`, reuseExistingServer: process.env.GLOW_REUSE_SERVER === '1', timeout: 60_000 },
});
