// Production cold-cache lab measurement. Run separately from builds/tests.
// POIETRA_PERF_URL=http://127.0.0.1:5188 POIETRA_PERF_OUTPUT=/tmp/home.json node scripts/measure-home.mjs
import { chromium } from '@playwright/test';
import { mkdir, writeFile } from 'node:fs/promises';
import { dirname } from 'node:path';
import { environment, stats } from './benchmark-environment.mjs';

const url = process.env.POIETRA_PERF_URL || 'http://127.0.0.1:5188';
const output = process.env.POIETRA_PERF_OUTPUT || 'test-results/home-performance.json';
const runs = Number(process.env.POIETRA_PERF_RUNS || 5);
if (!Number.isInteger(runs) || runs < 1 || runs > 20) throw new Error('POIETRA_PERF_RUNS must be 1..20');
const conditions = {
  viewport: { width: 390, height: 844 }, deviceScaleFactor: 1, isMobile: true,
  latencyMs: 150, downloadBytesPerSecond: 200000, uploadBytesPerSecond: 93750, cpuSlowdown: 4,
  cache: 'New browser context per navigation; HTTP cache disabled',
  observation: 'Until network idle, fonts ready and two animation frames; no input or scrolling',
  longTasks: 'Sum of max(0, duration-50ms) across observed long tasks; not Lighthouse TBT',
  cls: 'Maximum session window: <1s between shifts, <5s total; recent-input shifts excluded',
};
const measuredEnvironment = environment();
const browser = await chromium.launch({ headless: true, ...(process.env.CHROME_PATH ? { executablePath: process.env.CHROME_PATH } : {}) });
const samples = [];
try {
  for (let run = 0; run < runs; run++) for (const locale of run % 2 ? ['ja-JP', 'en-US'] : ['en-US', 'ja-JP']) {
    const context = await browser.newContext({ locale, viewport: conditions.viewport, deviceScaleFactor: 1, isMobile: true });
    try {
      const page = await context.newPage();
      const failures = [], sockets = [], responses = [];
      page.on('pageerror', error => failures.push(error.message));
      page.on('requestfailed', request => failures.push(`${new URL(request.url()).pathname}: ${request.failure()?.errorText}`));
      page.on('websocket', socket => sockets.push(new URL(socket.url()).pathname));
      page.on('response', response => {
        const path = new URL(response.url()).pathname;
        if (response.status() >= 400) failures.push(`${path}: HTTP ${response.status()}`);
        responses.push({ path, status: response.status(), contentEncoding: response.headers()['content-encoding'] || 'identity' });
      });
      const cdp = await context.newCDPSession(page);
      await cdp.send('Network.enable');
      await cdp.send('Network.setCacheDisabled', { cacheDisabled: true });
      await cdp.send('Network.emulateNetworkConditions', { offline: false, latency: conditions.latencyMs, downloadThroughput: conditions.downloadBytesPerSecond, uploadThroughput: conditions.uploadBytesPerSecond });
      await cdp.send('Emulation.setCPUThrottlingRate', { rate: conditions.cpuSlowdown });
      await page.addInitScript(() => {
        const metrics = { lcpMs: 0, lcpElement: null, cls: 0, longTaskBlockingMs: 0 };
        let start = 0, previous = 0, score = 0;
        const observers = [];
        function observe(type, consume) {
          const observer = new PerformanceObserver(list => consume(list.getEntries()));
          observer.observe({ type, buffered: true }); observers.push({ observer, consume });
        }
        observe('largest-contentful-paint', entries => { for (const entry of entries) { metrics.lcpMs = entry.startTime; metrics.lcpElement = entry.element?.tagName; } });
        observe('layout-shift', entries => {
          for (const entry of entries) if (!entry.hadRecentInput) {
            if (previous && entry.startTime - previous < 1000 && entry.startTime - start < 5000) score += entry.value;
            else { start = entry.startTime; score = entry.value; }
            previous = entry.startTime; metrics.cls = Math.max(metrics.cls, score);
          }
        });
        observe('longtask', entries => { for (const entry of entries) metrics.longTaskBlockingMs += Math.max(0, entry.duration - 50); });
        window.readHomeMetrics = () => {
          for (const { observer, consume } of observers) consume(observer.takeRecords());
          return { ...metrics };
        };
      });
      await page.goto(url, { waitUntil: 'networkidle', timeout: 60000 });
      await page.evaluate(async () => {
        await document.fonts.ready;
        await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
      });
      const sample = { run: run + 1, locale, ...await page.evaluate(() => {
        const navigation = performance.getEntriesByType('navigation')[0];
        return {
          ...window.readHomeMetrics(), observedUntilMs: performance.now(), language: document.documentElement.lang,
          fcpMs: performance.getEntriesByName('first-contentful-paint')[0]?.startTime,
          ttfbMs: navigation.responseStart, documentTransferBytes: navigation.transferSize,
          documentDecodedBytes: navigation.decodedBodySize,
          resources: performance.getEntriesByType('resource').map(entry => ({ path: new URL(entry.name).pathname, transferBytes: entry.transferSize, decodedBytes: entry.decodedBodySize, startMs: entry.startTime, durationMs: entry.duration })),
        };
      }), responses, sockets };
      if (failures.length) throw new Error(failures.join('\n'));
      if (!sample.lcpMs || !sample.fcpMs || sample.language !== locale.slice(0, 2)) throw new Error('Missing paint timing or incorrect language.');
      if (sockets.length || sample.resources.some(entry => /\.wasm$|\/assets\/(?:bootstrap|editor|studio|svg|media|kernel|painter|renderer|export)[^/]*\.js$/i.test(entry.path))) throw new Error('Homepage loaded the editor or opened a room.');
      sample.resourceTransferBytes = sample.resources.reduce((sum, entry) => sum + entry.transferBytes, 0);
      sample.javascriptDecodedBytes = sample.resources.filter(entry => /\.[cm]?js$/.test(entry.path)).reduce((sum, entry) => sum + entry.decodedBytes, 0);
      samples.push(sample);
      console.log(JSON.stringify({ run: sample.run, locale, lcpMs: sample.lcpMs, fcpMs: sample.fcpMs, cls: sample.cls, longTaskBlockingMs: sample.longTaskBlockingMs, resourceTransferBytes: sample.resourceTransferBytes }));
    } finally { await context.close(); }
  }
  const summary = ['en-US', 'ja-JP'].map(locale => ({ locale, ...Object.fromEntries(['lcpMs', 'fcpMs', 'cls', 'ttfbMs', 'longTaskBlockingMs', 'resourceTransferBytes', 'javascriptDecodedBytes'].map(key => [key, stats(samples.filter(sample => sample.locale === locale).map(sample => sample[key]))])) }));
  await mkdir(dirname(output), { recursive: true });
  await writeFile(output, JSON.stringify({ url, measuredAt: new Date().toISOString(), environment: measuredEnvironment, browser: browser.version(), conditions, summary, samples }, null, 2) + '\n');
  console.log(`Saved ${output}`);
} finally { await browser.close(); }
