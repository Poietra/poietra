// Opt-in production project-preview benchmark; isolated loopback rooms only.
import { chromium, expect } from '@playwright/test';
import * as Y from 'yjs';
import { WebsocketProvider } from 'y-websocket';
import WebSocket from 'ws';
import { mkdir, writeFile } from 'node:fs/promises';
import { dirname } from 'node:path';
import { applyChanges } from '../shared/document.js';
import { defaultState } from '../shared/model.js';
import { environment, stats } from './benchmark-environment.mjs';

const base = new URL(process.env.POIETRA_PERF_URL || 'http://127.0.0.1:5195');
if (!['localhost', '127.0.0.1', '[::1]'].includes(base.hostname)) throw new Error('Use an isolated loopback server.');
const output = process.env.POIETRA_PERF_OUTPUT || 'test-results/project-preview-performance.json';
const measuredEnvironment = environment(), browser = await chromium.launch({ headless: true }), results = [];
await mkdir(dirname(output), { recursive: true });
try {
  for (const count of [100, 500]) {
    const room = crypto.randomUUID(), doc = new Y.Doc();
    const provider = new WebsocketProvider(new URL('/sync', base).href.replace('http:', 'ws:'), room, doc, { WebSocketPolyfill: WebSocket, disableBc: true, connect: false });
    const context = await browser.newContext({ viewport: { width: 1440, height: 900 } });
    try {
      await new Promise((resolve, reject) => {
        const timer = setTimeout(() => reject(new Error('Seed timeout')), 15000);
        provider.on('sync', ready => { if (ready) { clearTimeout(timer); resolve(); } }); provider.connect();
      });
      const scene = { id: 's', name: 'Scene', width: 1280, height: 720, background: '#08090b', objects: {}, compositionOrder: ['a', 'b'], compositions: {}, transitions: { t: { id: 't', fromId: 'a', toId: 'b', duration: 4000, tracks: {} } }, audioTracks: {} };
      for (const id of ['a', 'b']) scene.compositions[id] = { id, name: id, duration: 1000, states: {} };
      for (let i = 0; i < count; i++) {
        const id = `o${i}`;
        scene.objects[id] = { id, name: id, kind: 'circle', order: i, locked: false, groupId: null };
        for (const id of ['a', 'b']) scene.compositions[id].states[`o${i}`] = defaultState('circle', { x: 30 + i % 25 * 42 + (id === 'b' ? 150 : 0), y: 30 + Math.floor(i / 25) * 32, width: 20, height: 20 });
      }
      applyChanges(doc, Object.entries({ version: 1, name: 'Preview benchmark', sceneOrder: ['s'], scenes: { s: scene } }).map(([key, value]) => ({ path: [key], value })));
      const page = await context.newPage(), errors = [];
      page.on('pageerror', error => errors.push(error.message));
      await page.goto(new URL(`/?room=${room}`, base).href);
      await expect(page.getByText('Live', { exact: true })).toBeVisible({ timeout: 20000 });
      await expect(page.getByTestId('stage-main').locator('[data-object-id]')).toHaveCount(count);
      await page.getByRole('button', { name: 'Preview project', exact: true }).click();
      await expect(page.getByTestId('project-preview-frame').locator('canvas')).toHaveCSS('visibility', 'visible');
      const cdp = await context.newCDPSession(page); await cdp.send('Performance.enable');
      const metrics = async () => Object.fromEntries((await cdp.send('Performance.getMetrics')).metrics.map(({ name, value }) => [name, value]));
      await page.evaluate(() => {
        let current;
        const html = Object.getOwnPropertyDescriptor(Element.prototype, 'innerHTML');
        Object.defineProperty(Element.prototype, 'innerHTML', { ...html, set(value) {
          if (current && (this.matches('.project-preview-svg') || this.closest('.project-preview-svg'))) { current.svgWrites++; current.svgCharacters += String(value).length; }
          html.set.call(this, value);
        } });
        const draw = CanvasRenderingContext2D.prototype.drawImage;
        CanvasRenderingContext2D.prototype.drawImage = function(...args) {
          const result = draw.apply(this, args);
          if (current && this.canvas.closest?.('[data-testid="project-preview-frame"]')) current.presented.push(performance.now());
          return result;
        };
        window.previewBenchmark = {
          begin() { current = { svgWrites: 0, svgCharacters: 0, presented: [], raf: [] }; const tick = now => { if (current) { current.raf.push(now); requestAnimationFrame(tick); } }; requestAnimationFrame(tick); },
          end() { const result = current; current = null; return result; },
        };
      });
      const samples = [];
      for (let run = -1; run < 3; run++) {
        await page.getByRole('slider', { name: 'Project preview position', exact: true }).fill('1000');
        await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
        const before = await metrics();
        await page.evaluate(() => window.previewBenchmark.begin());
        await page.getByRole('button', { name: 'プロジェクトを再生', exact: true }).click();
        await page.waitForTimeout(3500); // Fixed workload duration, not an assertion wait.
        await page.getByRole('button', { name: 'プロジェクトの再生を停止', exact: true }).click();
        const measured = await page.evaluate(() => window.previewBenchmark.end()), after = await metrics();
        const intervals = values => values.slice(1).map((value, index) => value - values[index]);
        measured.publicationIntervals = intervals(measured.presented); measured.rafIntervals = intervals(measured.raf);
        measured.cpu = Object.fromEntries(['ScriptDuration', 'TaskDuration', 'LayoutDuration', 'RecalcStyleDuration'].map(key => [key, (after[key] - before[key]) * 1000]));
        if (run >= 0) samples.push(measured);
      }
      if (errors.length) throw new Error(errors.join('\n'));
      results.push({ objects: count, samples, taskMsPerPublication: stats(samples.map(s => s.cpu.TaskDuration / s.presented.length)), scriptMsPerPublication: stats(samples.map(s => s.cpu.ScriptDuration / s.presented.length)), publicationIntervalMs: stats(samples.flatMap(s => s.publicationIntervals)), rafIntervalMs: stats(samples.flatMap(s => s.rafIntervals)), svgWrites: samples.map(s => s.svgWrites), svgCharacters: samples.map(s => s.svgCharacters) });
    } finally { provider.destroy(); doc.destroy(); await context.close(); }
  }
  await writeFile(output, JSON.stringify({ measuredAt: new Date().toISOString(), environment: measuredEnvironment, browser: browser.version(), conditions: { server: 'Production Node on loopback', viewport: { width: 1440, height: 900 }, warmup: 'One 3.5-second transition pass per size', samples: 'Three 3.5-second transition passes; seek to 1000 ms of a 6000 ms Scene before each pass; 500 or 100 moving circles', measurement: 'CDP Performance task/script/layout/style duration deltas, native display drawImage publication times, rAF callbacks and SVG innerHTML writes; hooks and play/pause included', exclusions: 'No video/audio, WAN or hardware GPU; not physical FPS or end-to-end input latency' }, results }, null, 2) + '\n');
  console.log(JSON.stringify(results.map(({ samples, ...summary }) => summary), null, 2));
} finally { await browser.close(); }
