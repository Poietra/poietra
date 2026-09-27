import { writeFile } from 'node:fs/promises';
import { expect, test } from '@playwright/test';
import type {} from './fixtures/effects-write';

test('records the sixteen-object and complete calculus timeline measurements', async ({ page, browser }, testInfo) => {
  test.skip(!process.env.RUN_WRITE_BENCHMARK, 'Run performance measurements separately with an otherwise idle GPU.');
  await page.goto('/tests/e2e/fixtures/effects-write.html');
  await page.waitForFunction(() => Boolean(window.effectsWriteFixture));
  for (const scenario of ['write', 'move-rotate', 'calculus'] as const) {
    const report = await page.evaluate(scenario => scenario === 'calculus' ? window.effectsWriteFixture.calculus() : window.effectsWriteFixture.benchmark(scenario === 'write'), scenario);
    expect(report.backend).toBe('webgl2');
    expect(report.frames).toBe(scenario === 'calculus' ? 399 : 60);
    expect(report.objects).toBe(scenario === 'calculus' ? 25 : 16);
    await writeFile(testInfo.outputPath(`${scenario}.json`), JSON.stringify({ revision: process.env.BENCHMARK_REVISION ?? 'unrecorded', browserVersion: browser.version(), measuredAt: new Date().toISOString(), ...report }, null, 2));
    console.log(JSON.stringify({ scenario, meanMs: report.meanMs, medianMs: report.medianMs, p95Ms: report.p95Ms, svgImageLoads: report.svgImageLoads, textureUploads: report.textureUploads, segments: report.segments }));
  }
  await page.screenshot({ path: testInfo.outputPath('calculus-final.png'), fullPage: true });
});

