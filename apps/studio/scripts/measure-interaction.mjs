// Production editor drag/playback benchmark; disposable loopback rooms only.
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
const output = process.env.POIETRA_PERF_OUTPUT || 'test-results/interaction-performance.json';
const measuredEnvironment = environment();
await mkdir(dirname(output), { recursive: true });
const browser = await chromium.launch({ headless: true });
const results = [];
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
      const scene = { id: 's', name: 'Scene', width: 1280, height: 720, background: '#08090b', objects: {}, compositionOrder: ['a', 'b'], compositions: {}, transitions: { t: { id: 't', fromId: 'a', toId: 'b', duration: 1000, tracks: {} } }, audioTracks: {} };
      for (const id of ['a', 'b']) scene.compositions[id] = { id, name: 'Composition ' + id, duration: 1000, states: {} };
      for (let i = 0; i < count; i++) {
        const id = i ? `o${i}` : 'circle';
        scene.objects[id] = { id, name: i ? id : 'Circle', kind: 'circle', order: i, groupId: null, locked: false };
        for (const comp of ['a', 'b']) scene.compositions[comp].states[id] = defaultState('circle', { x: 40 + i % 25 * 48 + (comp === 'b' ? 12 : 0), y: 30 + Math.floor(i / 25) * 32, width: i ? 20 : 42, height: i ? 20 : 42 });
      }
      applyChanges(doc, Object.entries({ version: 1, name: 'Interaction benchmark', sceneOrder: ['s'], scenes: { s: scene } }).map(([key, value]) => ({ path: [key], value })));
      const page = await context.newPage(), errors = [];
      page.on('pageerror', error => errors.push(error.message));
      await page.goto(new URL(`/?room=${room}`, base).href);
      await expect(page.getByText('Live', { exact: true })).toBeVisible({ timeout: 20000 });
      await expect(page.getByTestId('stage-main').locator('[data-object-id]')).toHaveCount(count);
      await page.getByRole('button', { name: 'Circle', exact: true }).click();
      const cdp = await context.newCDPSession(page);
      await cdp.send('Profiler.enable'); await cdp.send('Profiler.setSamplingInterval', { interval: 1000 }); await cdp.send('Profiler.start');
      const stage = page.getByTestId('stage-main'), item = stage.locator('.scene-svg [data-object-id="circle"]');
      const drag = [];
      for (let run = -1; run < 3; run++) {
        const box = await item.boundingBox(), surface = await stage.boundingBox();
        const x = box.x + box.width / 2, y = box.y + box.height / 2;
        await page.mouse.move(x, y);
        await page.mouse.down();
        await page.evaluate(({ x, scale }) => {
          const target = document.querySelector('[data-testid="stage-main"] .scene-svg [data-object-id="circle"]');
          const position = () => Number(target?.getAttribute('transform')?.match(/translate\(([^ ,)]+)/)?.[1]);
          const initial = position(), pending = [], measured = [], domLatencies = [], inputTimes = [], intervals = [];
          let previous = 0, raf;
          const tick = now => { if (previous) intervals.push(now - previous); previous = now; raf = requestAnimationFrame(tick); }; raf = requestAnimationFrame(tick);
          const onMove = e => {
            if (!e.buttons) return;
            const start = performance.now(); inputTimes.push(start);
            pending.push({ x: initial + (e.clientX - x) * scale, start });
          };
          window.addEventListener('pointermove', onMove, true);
          const observer = new MutationObserver(() => {
            const value = Number(document.querySelector('[data-testid="stage-main"] .scene-svg [data-object-id="circle"]')?.getAttribute('transform')?.match(/translate\(([^ ,)]+)/)?.[1]);
            const index = pending.findLastIndex(sample => Math.abs(sample.x - value) < .2);
            if (index < 0) return;
            const sample = pending[index]; pending.splice(0, index + 1);
            domLatencies.push(performance.now() - sample.start);
            requestAnimationFrame(() => requestAnimationFrame(() => measured.push(performance.now() - sample.start)));
          });
          observer.observe(document.querySelector('[data-testid="stage-main"]'), { subtree: true, attributes: true, childList: true });
          window.stopDragMeasurement = async () => {
            await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
            observer.disconnect(); window.removeEventListener('pointermove', onMove, true); cancelAnimationFrame(raf);
            return { latencies: measured, domLatencies, inputIntervals: inputTimes.slice(1).map((time, i) => time - inputTimes[i]), intervals };
          };
        }, { x, scale: 1280 / surface.width });
        // Deliver trusted input at a nominal 60 Hz; a busy page can delay delivery.
        for (let i = 0; i < 60; i++) {
          await page.mouse.move(x + 60 * Math.sin((i + 1) / 60 * Math.PI), y);
          await new Promise(resolve => setTimeout(resolve, 16));
        }
        await page.mouse.up();
        const sample = await page.evaluate(() => window.stopDragMeasurement());
        if (run >= 0) { if (sample.latencies.length < 20) throw new Error('Too few drag updates observed: ' + sample.latencies.length); drag.push(sample); }
      }
      await page.evaluate(() => {
        window.playbackIntervals = []; let previous = 0;
        window.recordPlayback = true;
        const tick = now => { if (!window.recordPlayback) return; if (previous) window.playbackIntervals.push(now - previous); previous = now; requestAnimationFrame(tick); };
        requestAnimationFrame(tick);
      });
      await page.getByRole('button', { name: 'シーンを再生', exact: true }).click();
      await expect(page.getByRole('button', { name: '一時停止', exact: true })).toBeVisible();
      await expect(page.getByRole('button', { name: 'シーンを再生', exact: true })).toBeVisible({ timeout: 15000 });
      const playback = await page.evaluate(() => { window.recordPlayback = false; return window.playbackIntervals; });
      const { profile } = await cdp.send('Profiler.stop');
      await writeFile(`${output}.${count}.cpuprofile`, JSON.stringify(profile));
      if (errors.length) throw new Error(errors.join('\n'));
      const result = { objects: count, drag, playbackIntervalsMs: playback, dragLatencyMs: stats(drag.flatMap(s => s.latencies)), dragDomLatencyMs: stats(drag.flatMap(s => s.domLatencies)), deliveredInputIntervalMs: stats(drag.flatMap(s => s.inputIntervals)), playbackIntervalMs: stats(playback) };
      results.push(result); console.log(JSON.stringify({ objects: count, dragLatencyMs: result.dragLatencyMs, dragDomLatencyMs: result.dragDomLatencyMs, deliveredInputIntervalMs: result.deliveredInputIntervalMs, playbackIntervalMs: result.playbackIntervalMs }));
    } finally { provider.destroy(); doc.destroy(); await context.close(); }
  }
  await writeFile(output, JSON.stringify({ measuredAt: new Date().toISOString(), environment: measuredEnvironment, browser: browser.version(), conditions: { server: 'Production Node on loopback', objects: [100, 500], clients: 1, viewport: { width: 1440, height: 900 }, drag: '60 trusted pointer moves at nominal 60 Hz, 1 warmup + 3 runs; DOM update + two rAF callbacks after pointer delivery', inputDiagnostics: 'Also records capture-listener to DOM mutation and actual delivered pointer spacing; excludes pre-delivery waiting and is not paint latency', playback: 'Three-second Scene, two one-second holds and one-second transition; rAF spacing, not physical FPS', profiling: 'CDP CPU sampler at 1 ms; includes measurement overhead', exclusions: 'No media, WAN or hardware GPU; not field INP' }, results }, null, 2) + '\n');
} finally { await browser.close(); }
