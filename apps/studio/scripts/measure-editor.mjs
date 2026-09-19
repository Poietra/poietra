// Real production UI: sequential keyboard nudges through local WebSocket peers.
// Creates disposable rooms. Use a separate local server/data directory.
import { chromium, expect } from '@playwright/test';
import * as Y from 'yjs';
import { WebsocketProvider } from 'y-websocket';
import WebSocket from 'ws';
import { mkdir, writeFile } from 'node:fs/promises';
import { dirname } from 'node:path';
import { applyChanges } from '../shared/document.js';
import { defaultState } from '../shared/model.js';
import { environment } from './benchmark-environment.mjs';

const url = new URL(process.env.POIETRA_PERF_URL || 'http://127.0.0.1:5188');
if (!['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname)) throw new Error('Use an isolated loopback server for this room-creating benchmark.');
const output = process.env.POIETRA_PERF_OUTPUT || 'test-results/editor-performance.json';
const samples = Number(process.env.POIETRA_PERF_SAMPLES || 30);
if (!Number.isInteger(samples) || samples < 5 || samples > 100) throw new Error('POIETRA_PERF_SAMPLES must be 5..100');
const measuredEnvironment = environment();
const browser = await chromium.launch({ headless: true, ...(process.env.CHROME_PATH ? { executablePath: process.env.CHROME_PATH } : {}) });
const results = [];
function stats(values) {
  const sorted = [...values].sort((a, b) => a - b);
  return { n: values.length, p50: sorted[Math.floor(values.length / 2)], p95: sorted[Math.ceil(values.length * .95) - 1], min: sorted[0], max: sorted.at(-1) };
}
function fixture(count) {
  const objects = {}, states = {};
  for (let index = 0; index < count; index++) {
    const id = index === 0 ? 'circle' : `object-${index}`;
    objects[id] = { id, name: index === 0 ? 'Circle' : `Circle ${index}`, kind: 'circle', order: index, locked: false, groupId: null };
    states[id] = defaultState('circle', { x: 40 + index % 25 * 48, y: 30 + Math.floor(index / 25) * 32, width: 20, height: 20 });
  }
  return { version: 1, name: 'Performance fixture', sceneOrder: ['scene-1'], scenes: { 'scene-1': {
    id: 'scene-1', name: 'Scene', width: 1280, height: 720, background: '#08090b', objects,
    compositionOrder: ['comp-1'], compositions: { 'comp-1': { id: 'comp-1', name: 'Composition 1', duration: 1000, states } }, transitions: {}, audioTracks: {},
  } } };
}
try {
  for (const objects of [100, 500]) for (const clients of [2, 4]) {
    const room = crypto.randomUUID(), contexts = [], pages = [], errors = [], startupMs = [], traffic = [];
    const doc = new Y.Doc();
    const endpoint = new URL('/sync', url); endpoint.protocol = 'ws:';
    const provider = new WebsocketProvider(endpoint.href, room, doc, { WebSocketPolyfill: WebSocket, disableBc: true });
    try {
      await new Promise((resolve, reject) => {
        const timer = setTimeout(() => reject(new Error('Seed connection timed out')), 15000);
        provider.on('sync', ready => { if (ready) { clearTimeout(timer); resolve(); } });
      });
      applyChanges(doc, Object.entries(fixture(objects)).map(([key, value]) => ({ path: [key], value })), 'benchmark-seed');
      for (let client = 0; client < clients; client++) {
        const context = await browser.newContext({ viewport: { width: 1440, height: 900 }, locale: 'en-US' }); contexts.push(context);
        const page = await context.newPage(); pages.push(page);
        const bytes = { sent: 0, received: 0 }; traffic.push(bytes);
        page.on('pageerror', error => errors.push(error.message));
        page.on('websocket', socket => {
          socket.on('framesent', event => bytes.sent += Buffer.byteLength(event.payload));
          socket.on('framereceived', event => bytes.received += Buffer.byteLength(event.payload));
        });
        const start = performance.now();
        await page.goto(new URL(`/?room=${room}`, url).href);
        await expect(page.getByText('Live', { exact: true })).toBeVisible({ timeout: 15000 });
        await expect(page.locator('[data-testid="stage-main"] [data-object-id]')).toHaveCount(objects);
        startupMs.push(performance.now() - start);
        await page.getByRole('button', { name: 'Circle', exact: true }).click();
        await page.evaluate(() => {
          const selector = '[data-testid="stage-main"] .scene-svg [data-object-id="circle"]';
          window.benchmarkX = () => Number(document.querySelector(selector)?.getAttribute('transform')?.match(/translate\(([^ ,)]+)/)?.[1]);
          window.armNudge = expected => {
            window.nudgeStart = null;
            const onKey = event => { if (event.key === 'ArrowRight') window.nudgeStart = performance.timeOrigin + performance.now(); };
            window.addEventListener('keydown', onKey, { capture: true, once: true });
            window.nudgeResult = new Promise((resolve, reject) => {
              let done = false;
              const timer = setTimeout(() => { observer.disconnect(); reject(new Error('Nudge did not reach the stage')); }, 10000);
              const observer = new MutationObserver(() => {
                if (done || window.benchmarkX() !== expected) return;
                done = true; observer.disconnect(); clearTimeout(timer);
                // Two rAF callbacks delimit an opportunity to present the updated stage.
                requestAnimationFrame(() => requestAnimationFrame(() => {
                  window.removeEventListener('keydown', onKey, true);
                  resolve({ start: window.nudgeStart, presented: performance.timeOrigin + performance.now(), x: window.benchmarkX() });
                }));
              });
              observer.observe(document.querySelector('[data-testid="stage-main"]'), { subtree: true, childList: true, attributes: true });
            });
          };
        });
      }
      // The seed client must not remain an extra participant in measured edits.
      provider.destroy(); doc.destroy();
      await pages[0].getByRole('button', { name: 'Circle', exact: true }).focus();
      const measurements = [];
      for (let index = 0; index < samples + 3; index++) {
        const expected = await pages[0].evaluate(() => window.benchmarkX() + 1);
        if (!Number.isFinite(expected)) throw new Error('Missing stage transform.');
        if (index === 3) for (const bytes of traffic) { bytes.sent = 0; bytes.received = 0; }
        await Promise.all(pages.map(page => page.evaluate(x => window.armNudge(x), expected)));
        await pages[0].keyboard.press('ArrowRight');
        const observed = await Promise.all(pages.map(page => page.evaluate(() => window.nudgeResult)));
        if (observed.some(value => value.x !== expected) || observed[0].start == null) throw new Error('Nudge observation is incomplete.');
        if (index >= 3) measurements.push({ localMs: observed[0].presented - observed[0].start, peerMs: observed.slice(1).map(value => value.presented - observed[0].start) });
      }
      if (errors.length) throw new Error(errors.join('\n'));
      const result = { objects, clients, startupMs, localMs: stats(measurements.map(value => value.localMs)), slowestPeerMs: stats(measurements.map(value => Math.max(...value.peerMs))), trafficBytes: traffic, samples: measurements };
      results.push(result);
      console.log(JSON.stringify({ objects, clients, localMs: result.localMs, slowestPeerMs: result.slowestPeerMs }));
    } finally {
      provider.destroy(); doc.destroy();
      for (const context of contexts) await context.close();
    }
  }
  await mkdir(dirname(output), { recursive: true });
  await writeFile(output, JSON.stringify({ measuredAt: new Date().toISOString(), environment: measuredEnvironment, browser: browser.version(), conditions: { production: true, viewport: { width: 1440, height: 900 }, server: 'Node on loopback; unthrottled network and CPU', fixtures: 'One scene, one composition, circles only; no audio/video', samples, warmup: 3, metric: 'Trusted ArrowRight keydown to matching stage SVG transform plus two rAF callbacks; presentation opportunity, not physical display or field INP. Peer clocks use performance.timeOrigin + performance.now().', startup: 'Node clock around navigation plus Playwright readiness assertions; includes automation polling, not a Web Vital', traffic: 'WebSocket payload bytes during sampled edits; includes awareness, excludes frame/TCP overhead', limitations: 'Single browser process with isolated contexts on one machine; no WAN, workerd, offline recovery or long-session memory measurement' }, results }, null, 2) + '\n');
} finally { await browser.close(); }
