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
const staticHold = process.env.POIETRA_PERF_HOLD === '1';
const editor = process.env.POIETRA_PERF_EDITOR === '1';
const frameTestId = editor ? 'stage-main' : 'project-preview-frame';
const sliderName = editor ? '再生位置' : 'Project preview position';
const playName = editor ? 'シーンを再生' : 'プロジェクトを再生';
const pauseName = editor ? '一時停止' : 'プロジェクトの再生を停止';
const optionalStats = values => values.length ? stats(values) : null;
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
      for (const id of ['a', 'b']) scene.compositions[id] = { id, name: id, duration: staticHold ? 5000 : 1000, states: {} };
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
      if (!editor) await page.getByRole('button', { name: 'Preview project', exact: true }).click();
      await expect(page.getByTestId(frameTestId).locator('canvas')).toHaveCSS('visibility', 'visible');
      const cdp = await context.newCDPSession(page); await cdp.send('Performance.enable');
      const metrics = async () => Object.fromEntries((await cdp.send('Performance.getMetrics')).metrics.map(({ name, value }) => [name, value]));
      await page.evaluate(({ frameTestId, editor }) => {
        let current;
        const root = document.querySelector(`[data-testid="${frameTestId}"]`), selector = editor ? '.scene-svg' : '.project-preview-svg';
        const observer = new MutationObserver(records => {
          if (current) current.svgMutations += records.filter(record => (record.target.nodeType === Node.ELEMENT_NODE ? record.target : record.target.parentElement)?.closest(selector)).length;
        });
        observer.observe(root, { attributes: true, childList: true, characterData: true, subtree: true });
        const html = Object.getOwnPropertyDescriptor(Element.prototype, 'innerHTML');
        Object.defineProperty(Element.prototype, 'innerHTML', { ...html, set(value) {
          if (current && root.contains(this) && this.closest(selector)) { current.svgWrites++; current.svgCharacters += String(value).length; }
          html.set.call(this, value);
        } });
        const draw = CanvasRenderingContext2D.prototype.drawImage;
        CanvasRenderingContext2D.prototype.drawImage = function(...args) {
          const result = draw.apply(this, args);
          if (current && root.contains(this.canvas)) current.presented.push(performance.now());
          return result;
        };
        window.previewBenchmark = {
          begin() { current = { svgWrites: 0, svgCharacters: 0, svgMutations: 0, presented: [], raf: [] }; const tick = now => { if (current) { current.raf.push(now); requestAnimationFrame(tick); } }; requestAnimationFrame(tick); },
          end() { const result = current; current = null; return result; },
        };
      }, { frameTestId, editor });
      const samples = [];
      for (let run = -1; run < 3; run++) {
        await page.getByRole('slider', { name: sliderName, exact: true }).fill(staticHold ? '0' : '1000');
        await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
        const before = await metrics();
        await page.evaluate(() => window.previewBenchmark.begin());
        await page.getByRole('button', { name: playName, exact: true }).click();
        await page.waitForTimeout(3500); // Fixed workload duration, not an assertion wait.
        await page.getByRole('button', { name: pauseName, exact: true }).click();
        const measured = await page.evaluate(() => window.previewBenchmark.end()), after = await metrics();
        const position = Number(await page.getByRole('slider', { name: sliderName, exact: true }).inputValue());
        expect(position).toBeGreaterThan(staticHold ? 3000 : 4000);
        expect(position).toBeLessThan(staticHold ? 5000 : 6000);
        const intervals = values => values.slice(1).map((value, index) => value - values[index]);
        measured.publicationIntervals = intervals(measured.presented); measured.rafIntervals = intervals(measured.raf);
        measured.cpu = Object.fromEntries(['ScriptDuration', 'TaskDuration', 'LayoutDuration', 'RecalcStyleDuration'].map(key => [key, (after[key] - before[key]) * 1000]));
        if (run >= 0) samples.push(measured);
      }
      if (errors.length) throw new Error(errors.join('\n'));
      const publications = samples.flatMap(s => s.presented.length ? [s] : []);
      results.push({ objects: count, samples, taskMsPerPass: stats(samples.map(s => s.cpu.TaskDuration)), scriptMsPerPass: stats(samples.map(s => s.cpu.ScriptDuration)), publicationCounts: samples.map(s => s.presented.length), taskMsPerPublication: optionalStats(publications.map(s => s.cpu.TaskDuration / s.presented.length)), scriptMsPerPublication: optionalStats(publications.map(s => s.cpu.ScriptDuration / s.presented.length)), publicationIntervalMs: optionalStats(samples.flatMap(s => s.publicationIntervals)), rafIntervalMs: stats(samples.flatMap(s => s.rafIntervals)), svgWrites: samples.map(s => s.svgWrites), svgCharacters: samples.map(s => s.svgCharacters) });
    } finally { provider.destroy(); doc.destroy(); await context.close(); }
  }
  await writeFile(output, JSON.stringify({ measuredAt: new Date().toISOString(), environment: measuredEnvironment, browser: browser.version(), conditions: { view: editor ? 'Scene playback in editor' : 'Project preview', server: 'Production Node on loopback', viewport: { width: 1440, height: 900 }, warmup: `One 3.5-second ${staticHold ? 'hold' : 'transition'} pass per size`, samples: staticHold ? 'Three 3.5-second static passes; seek to 0 ms within a 5000 ms hold before each pass; 500 or 100 circles' : 'Three 3.5-second transition passes; seek to 1000 ms of a 6000 ms Scene before each pass; 500 or 100 moving circles', measurement: 'CDP Performance task/script/layout/style duration deltas, native display drawImage publication times, rAF callbacks and SVG innerHTML writes; hooks and play/pause included', exclusions: 'No video/audio, WAN or hardware GPU; not physical FPS or end-to-end input latency' }, results }, null, 2) + '\n');
  console.log(JSON.stringify(results.map(({ samples, ...summary }) => summary), null, 2));
} finally { await browser.close(); }
