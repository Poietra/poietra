// Development-only diagnostic counts; the fixture deliberately delays Canvas painting.
import { chromium, expect } from '@playwright/test';
import { mkdir, writeFile } from 'node:fs/promises';
import { dirname } from 'node:path';
import { countEditorRenders } from '../tests/e2e/render-counts.ts';
import { environment } from './benchmark-environment.mjs';

const base = new URL(process.env.POIETRA_PERF_URL || 'http://127.0.0.1:5288');
if (!['localhost', '127.0.0.1', '[::1]'].includes(base.hostname)) throw new Error('Use an isolated loopback development server.');
const output = process.env.POIETRA_PERF_OUTPUT || 'test-results/document-updates.json';
const measuredEnvironment = environment();
const browser = await chromium.launch();
try {
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } }), errors = [];
  page.on('pageerror', error => errors.push(error.message));
  await countEditorRenders(page);
  await page.goto(new URL('/tests/e2e/fixtures/painter-preview.html?room=' + crypto.randomUUID(), base).href);
  await expect(page.getByText('Live', { exact: true })).toBeVisible({ timeout: 15000 });
  await expect(page.getByTestId('stage-main').locator('.scene-hit-svg')).toHaveCount(1);
  await expect.poll(() => page.evaluate(() => window.painterPreview.active)).toBe(0);
  const cdp = await page.context().newCDPSession(page);
  await cdp.send('Profiler.enable'); await cdp.send('Profiler.start');
  const updates = await page.evaluate(async () => {
    window.renderCounts = {};
    const before = window.painterPreview.preparations;
    await window.painterPreview.positions(Array.from({ length: 12 }, (_, i) => 300 + i * 10));
    await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
    return { counts: window.renderCounts, preparations: window.painterPreview.preparations - before };
  });
  await expect.poll(() => page.evaluate(() => window.painterPreview.active)).toBe(0);
  const { profile } = await cdp.send('Profiler.stop');
  if (errors.length) throw new Error(errors.join('\n'));
  await mkdir(dirname(output), { recursive: true });
  await writeFile(output + '.cpuprofile', JSON.stringify(profile));
  await writeFile(output, JSON.stringify({
    measuredAt: new Date().toISOString(), environment: measuredEnvironment, browser: browser.version(),
    conditions: 'Development StrictMode: 12 position updates paced by rAF; sampled CPU, simulated delayed Canvas painter; counts include retries/double render, not production timing',
    ...updates,
  }, null, 2) + '\n');
  console.log(JSON.stringify(updates));
} finally { await browser.close(); }
