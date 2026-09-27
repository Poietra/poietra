import { expect, test, type TestInfo } from '@playwright/test';
import { writeFile } from 'node:fs/promises';
import type {} from './fixtures/effects';

async function saveReport(testInfo: TestInfo, name: string, report: unknown) {
  const path = testInfo.outputPath(`${name}.json`);
  await writeFile(path, JSON.stringify(report, null, 2));
  await testInfo.attach(name, { path, contentType: 'application/json' });
}

test.beforeEach(async ({ page }) => {
  await page.goto('/tests/e2e/fixtures/effects.html');
  await page.waitForFunction(() => Boolean(window.effectsFixture));
});

test('records warmed 1280x720 rendering timings for sixteen moving objects', async ({ page }, testInfo) => {
  for (const withWrite of [true, false]) {
    const report = await page.evaluate(withWrite => window.effectsFixture.benchmark(withWrite), withWrite);
    expect(report.backend).toBe('webgl2');
    expect(report.count).toBe(16);
    expect(report.timings).toHaveLength(report.frames);
    expect(report.timings.every(time => Number.isFinite(time) && time >= 0)).toBe(true);
    expect(report.meanMs).toBeGreaterThan(0);
    await saveReport(testInfo, withWrite ? 'effects-benchmark' : 'effects-benchmark-move-rotate', report);
  }
});
