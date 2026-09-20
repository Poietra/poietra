// Development-only component invocation counts; these are not frame timings.
import { chromium, expect } from '@playwright/test';
import { mkdir, writeFile } from 'node:fs/promises';
import { dirname } from 'node:path';
import { countEditorRenders } from '../tests/e2e/render-counts.ts';
import { environment } from './benchmark-environment.mjs';

const base = new URL(process.env.POIETRA_PERF_URL || 'http://127.0.0.1:5288');
if (!['localhost', '127.0.0.1', '[::1]'].includes(base.hostname)) throw new Error('Use an isolated loopback development server.');
const measuredEnvironment = environment();
const output = process.env.POIETRA_PERF_OUTPUT || 'test-results/subscription-performance.json';
const browser = await chromium.launch();
try {
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } }), errors = [];
  page.on('pageerror', error => errors.push(error.message));
  await countEditorRenders(page);
  await page.goto(new URL('/tests/e2e/fixtures/painter-preview.html?room=' + crypto.randomUUID(), base).href);
  await expect(page.getByText('Live', { exact: true })).toBeVisible({ timeout: 15000 });
  await expect(page.getByTestId('stage-main').locator('.scene-hit-svg')).toHaveCount(1);
  await expect.poll(() => page.evaluate(() => window.painterPreview.active)).toBe(0);
  const presence = await page.evaluate(async () => {
    window.renderCounts = {};
    await window.painterPreview.cursors(12);
    await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
    return window.renderCounts;
  });
  await page.getByRole('button', { name: 'シーンを再生', exact: true }).click();
  await expect(page.getByRole('button', { name: '一時停止', exact: true })).toBeVisible();
  const playback = await page.evaluate(async () => {
    for (let i = 0; i < 4; i++) await new Promise(requestAnimationFrame);
    window.renderCounts = {};
    const before = document.querySelector('.time-code strong').textContent;
    for (let i = 0; i < 24; i++) await new Promise(requestAnimationFrame);
    return { counts: window.renderCounts, before, after: document.querySelector('.time-code strong').textContent };
  });
  if (errors.length) throw new Error(errors.join('\n'));
  const result = {
    measuredAt: new Date().toISOString(), environment: measuredEnvironment, browser: browser.version(),
    runtime: 'Vite development; React StrictMode; counts include retries/double render',
    conditions: { presence: '12 updates paced by rAF', playback: '4 rAF warmup then 24 rAF observations', instrumentation: 'Component function entry counters; includes diagnostic overhead; not a production timing benchmark' },
    presence, playback,
  };
  await mkdir(dirname(output), { recursive: true });
  await writeFile(output, JSON.stringify(result, null, 2) + '\n');
  console.log(JSON.stringify({ presence, playback }));
} finally { await browser.close(); }
