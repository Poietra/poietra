// Cold mobile editor startup against disposable local rooms; run apart from builds/tests.
import { chromium } from '@playwright/test';
import * as Y from 'yjs';
import { WebsocketProvider } from 'y-websocket';
import WebSocket from 'ws';
import { mkdir, writeFile } from 'node:fs/promises';
import { dirname } from 'node:path';
import { applyChanges } from '../shared/document.js';
import { makeBlankScene } from '../shared/demo.js';
import { defaultState } from '../shared/model.js';
import { environment, stats } from './benchmark-environment.mjs';

const url = new URL(process.env.POIETRA_PERF_URL || 'http://127.0.0.1:5188');
if (!['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname)) throw new Error('Use an isolated loopback server for this room-creating benchmark.');
const runs = Number(process.env.POIETRA_PERF_RUNS || 3);
if (!Number.isInteger(runs) || runs < 1 || runs > 20) throw new Error('POIETRA_PERF_RUNS must be 1..20.');
const output = process.env.POIETRA_PERF_OUTPUT || 'test-results/startup-performance.json';
const conditions = {
  viewport: { width: 412, height: 823 }, deviceScaleFactor: 1, locale: 'ja-JP', isMobile: true,
  latencyMs: 150, downloadBytesPerSecond: 200000, uploadBytesPerSecond: 93750, cpuSlowdown: 4,
  cache: 'New browser context per navigation; HTTP cache disabled; no warmup',
  fixture: 'One Scene/Composition/circle, seeded through a separate local WebSocket before timing; no equation/media/font preparation for text objects',
  stageReady: 'First matching circle in the stage DOM plus two animation frames; a presentation opportunity, not physical display or a Web Vital',
  observation: 'Until the stage is ready, then network idle, fonts ready and two animation frames; no user input',
  network: 'CDP HTTP throttling with local Node/WebSocket persistence; does not model WAN WebSocket latency or workerd',
  longTasks: 'Sum of max(0, duration-50ms) across observed long tasks; not Lighthouse TBT',
};
const measuredEnvironment = environment();
const browser = await chromium.launch({ headless: true, ...(process.env.CHROME_PATH ? { executablePath: process.env.CHROME_PATH } : {}) });
const samples = [];
try {
  for (let run = 0; run < runs; run++) {
    const room = crypto.randomUUID(), doc = new Y.Doc();
    const endpoint = new URL('/sync', url); endpoint.protocol = 'ws:';
    const provider = new WebsocketProvider(endpoint.href, room, doc, { WebSocketPolyfill: WebSocket, disableBc: true, connect: false });
    const context = await browser.newContext({ locale: conditions.locale, viewport: conditions.viewport, deviceScaleFactor: conditions.deviceScaleFactor, isMobile: true });
    try {
      await new Promise((resolve, reject) => {
        const timer = setTimeout(() => reject(new Error('Seed connection timed out')), 15000);
        provider.on('sync', ready => { if (ready) { clearTimeout(timer); resolve(); } });
        provider.connect();
      });
      const scene = makeBlankScene('s', 'Scene 1');
      scene.objects.circle = { id: 'circle', name: 'Circle', kind: 'circle', order: 0, locked: false, groupId: null };
      scene.compositions[scene.compositionOrder[0]].states.circle = defaultState('circle');
      const project = { version: 1, name: 'Startup fixture', sceneOrder: ['s'], scenes: { s: scene } };
      applyChanges(doc, Object.entries(project).map(([key, value]) => ({ path: [key], value })), 'benchmark-seed');
      const page = await context.newPage(), failures = [], responses = [];
      page.on('pageerror', error => failures.push(error.message));
      page.on('requestfailed', request => failures.push(`${new URL(request.url()).pathname}: ${request.failure()?.errorText}`));
      page.on('response', response => {
        if (response.status() >= 400) failures.push(`HTTP ${response.status()}: ${new URL(response.url()).pathname}`);
        responses.push({ path: new URL(response.url()).pathname, contentEncoding: response.headers()['content-encoding'] || 'identity' });
      });
      const cdp = await context.newCDPSession(page);
      await cdp.send('Network.enable');
      await cdp.send('Network.setCacheDisabled', { cacheDisabled: true });
      await cdp.send('Network.emulateNetworkConditions', { offline: false, latency: conditions.latencyMs, downloadThroughput: conditions.downloadBytesPerSecond, uploadThroughput: conditions.uploadBytesPerSecond });
      await cdp.send('Emulation.setCPUThrottlingRate', { rate: conditions.cpuSlowdown });
      await page.addInitScript(() => {
        const metrics = { stageReadyMs: 0, lcpMs: 0, lcpElement: null, longTaskBlockingMs: 0 };
        const observers = [];
        function observe(type, consume) {
          const observer = new PerformanceObserver(list => consume(list.getEntries()));
          observer.observe({ type, buffered: true }); observers.push({ observer, consume });
        }
        observe('largest-contentful-paint', entries => { for (const entry of entries) { metrics.lcpMs = entry.startTime; metrics.lcpElement = entry.element?.tagName; } });
        observe('longtask', entries => { for (const entry of entries) metrics.longTaskBlockingMs += Math.max(0, entry.duration - 50); });
        const ready = new MutationObserver(() => {
          if (!document.querySelector('[data-testid="stage-main"] [data-object-id="circle"]')) return;
          ready.disconnect();
          requestAnimationFrame(() => requestAnimationFrame(() => { metrics.stageReadyMs = performance.now(); }));
        });
        ready.observe(document, { childList: true, subtree: true });
        window.readStartupMetrics = () => {
          for (const { observer, consume } of observers) consume(observer.takeRecords());
          return { ...metrics };
        };
      });
      await page.goto(new URL(`/?room=${room}`, url).href, { waitUntil: 'domcontentloaded', timeout: 60000 });
      await page.waitForFunction(() => window.readStartupMetrics().stageReadyMs > 0, undefined, { timeout: 60000 });
      await page.waitForLoadState('networkidle');
      await page.evaluate(async () => {
        await document.fonts.ready;
        await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
      });
      const sample = { run: run + 1, ...await page.evaluate(() => ({
        ...window.readStartupMetrics(), observedUntilMs: performance.now(),
        fcpMs: performance.getEntriesByName('first-contentful-paint')[0]?.startTime,
        resources: performance.getEntriesByType('resource').map(entry => ({ path: new URL(entry.name).pathname, transferBytes: entry.transferSize, decodedBytes: entry.decodedBodySize, startMs: entry.startTime, durationMs: entry.duration })),
      })), responses };
      if (failures.length) throw new Error(failures.join('\n'));
      if (!sample.lcpMs || !sample.fcpMs) throw new Error('Missing paint timing.');
      sample.javascriptDecodedBytes = sample.resources.filter(entry => /\.[cm]?js$/.test(entry.path)).reduce((sum, entry) => sum + entry.decodedBytes, 0);
      sample.resourceTransferBytes = sample.resources.reduce((sum, entry) => sum + entry.transferBytes, 0);
      samples.push(sample);
      console.log(JSON.stringify({ run: sample.run, fcpMs: sample.fcpMs, lcpMs: sample.lcpMs, stageReadyMs: sample.stageReadyMs, javascriptDecodedBytes: sample.javascriptDecodedBytes }));
    } finally { await context.close(); provider.destroy(); doc.destroy(); }
  }
  const summary = Object.fromEntries(['fcpMs', 'lcpMs', 'stageReadyMs', 'longTaskBlockingMs', 'javascriptDecodedBytes', 'resourceTransferBytes'].map(key => [key, stats(samples.map(sample => sample[key]))]));
  await mkdir(dirname(output), { recursive: true });
  await writeFile(output, JSON.stringify({ measuredAt: new Date().toISOString(), environment: measuredEnvironment, browser: browser.version(), conditions, summary, samples }, null, 2) + '\n');
  console.log(`Saved ${output}`);
} finally { await browser.close(); }
