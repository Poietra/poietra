import { defineConfig } from '@playwright/test';
import effects from './effects.config';

export default defineConfig({
  ...effects, testMatch: 'effects-benchmark.spec.ts',
  outputDir: '../../test-results/effects-benchmark',
});
