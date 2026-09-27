// Real production file picker -> durable room creation -> visible Canvas.
// Use isolated loopback storage; every sample creates two disposable rooms.
import { chromium, expect } from '@playwright/test';
import { createHash } from 'node:crypto';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname } from 'node:path';
import * as Y from 'yjs';
import { makeBlankScene } from '../shared/demo.js';
import { defaultState } from '../shared/model.js';
import { createProjectMessages } from '../src/editor/projects.js';
import { environment, stats } from './benchmark-environment.mjs';

const base = new URL(process.env.POIETRA_PERF_URL || 'http://127.0.0.1:5195');
if (!['localhost', '127.0.0.1', '[::1]'].includes(base.hostname)) throw new Error('Use an isolated loopback server.');
const output = process.env.POIETRA_PERF_OUTPUT || 'test-results/import-performance.json';
const measuredEnvironment = environment(), results = [];
const browser = await chromium.launch({ headless: true });
let gpu;
try {
  for (const [objects, compositions] of [[100, 2], [500, 6]]) {
    const scene = makeBlankScene('scene', 'Import benchmark');
    scene.objects = {}; scene.compositions = {}; scene.compositionOrder = []; scene.transitions = {};
    for (let i = 0; i < objects; i++) scene.objects[`o${i}`] = { id: `o${i}`, name: `Object ${i}`, kind: 'circle', order: i, groupId: null, locked: false };
    for (let c = 0; c < compositions; c++) {
      const id = `c${c}`; scene.compositionOrder.push(id);
      scene.compositions[id] = { id, name: `Composition ${c}`, accent: '#123456', duration: 1000,
        states: Object.fromEntries(Object.keys(scene.objects).map((id, i) => [id, defaultState('circle', {
          x: 25 + (i % 25) * 48 + c, y: 25 + Math.floor(i / 25) * 32, width: 20, height: 20, text: '日本語😀',
        })])) };
      if (c) scene.transitions[`t${c}`] = { id: `t${c}`, fromId: `c${c-1}`, toId: id, duration: 250, tracks: {} };
    }
    const project = { version: 1, name: 'Imported performance fixture', sceneOrder: [scene.id], scenes: { [scene.id]: scene } };
    const buffer = Buffer.from(JSON.stringify(project)), samples = [];
    // Portable JSON limits and the room's initial 2 MiB CRDT packet limit differ.
    // Check the actual handoff before timing so oversized inputs cannot masquerade
    // as a slow import. The staged Yjs document is disposed by the production API.
    const empty = new Y.Doc();
    let updateMessageBytes;
    try { updateMessageBytes = createProjectMessages(empty, project).updateMessage.byteLength; }
    finally { empty.destroy(); }
    const context = await browser.newContext({ viewport: { width: 1440, height: 900 } });
    try {
      if (process.env.POIETRA_PERF_DEBUG === '1') await context.addInitScript(() => {
        window.WebSocket = new Proxy(WebSocket, { construct(target, args) {
          const socket = new target(...args);
          socket.addEventListener('close', event => console.info('IMPORT_SOCKET_CLOSE', JSON.stringify({ code: event.code, reason: event.reason })));
          return socket;
        } });
      });
      await context.addInitScript(() => {
        let measurement = null, previous = null;
        const tick = now => {
          if (measurement && previous !== null) measurement.intervals.push(now - previous);
          previous = now; requestAnimationFrame(tick);
        };
        requestAnimationFrame(tick);
        document.addEventListener('change', event => {
          if (event.target instanceof HTMLInputElement && event.target.type === 'file' && event.target.files?.[0]?.name === 'benchmark.poietra.json') {
            measurement = { start: performance.timeOrigin + performance.now(), intervals: [] };
            previous = null; sessionStorage.setItem('poietra-import-measurement', JSON.stringify(measurement));
          }
        }, true);
        window.addEventListener('pagehide', () => {
          if (measurement) {
            measurement.beforeNavigationMs = performance.timeOrigin + performance.now() - measurement.start;
            sessionStorage.setItem('poietra-import-measurement', JSON.stringify(measurement));
          }
        });
      });
      for (let run = -1; run < 3; run++) {
        console.error(`Import ${objects} objects / ${compositions} Compositions: sample ${run + 1}/3 (${updateMessageBytes} preflight CRDT bytes)`);
        const page = await context.newPage(), originalRoom = crypto.randomUUID();
        try {
          if (process.env.POIETRA_PERF_DEBUG === '1') page.on('console', message => { if (message.text().startsWith('IMPORT_SOCKET_CLOSE')) console.error(message.text()); });
          await page.goto(new URL(`/?room=${originalRoom}`, base).href);
          await expect(page.getByText('Live', { exact: true })).toBeVisible({ timeout: 30000 });
          await expect(page.getByTestId('stage-main').locator('.scene-canvas')).toHaveCSS('visibility', 'visible', { timeout: 30000 });
          if (!gpu) gpu = await page.evaluate(() => {
            const gl = document.createElement('canvas').getContext('webgl2'), info = gl?.getExtension('WEBGL_debug_renderer_info');
            return info ? gl.getParameter(info.UNMASKED_RENDERER_WEBGL) : null;
          });
          await page.getByRole('button', { name: 'プロジェクトを開く', exact: true }).click();
          await page.getByLabel('プロジェクトファイル', { exact: true }).setInputFiles({ name: 'benchmark.poietra.json', mimeType: 'application/json', buffer });
          await expect(page).not.toHaveURL(new RegExp(originalRoom), { timeout: 30000 });
          await expect(page.getByRole('textbox', { name: 'Project name', exact: true })).toHaveValue(project.name, { timeout: 30000 });
          await expect(page.getByText('Live', { exact: true })).toBeVisible({ timeout: 30000 });
          await expect(page.getByTestId('stage-main').locator('.scene-svg [data-object-id]')).toHaveCount(objects);
          await expect(page.getByTestId('stage-main').locator('.scene-canvas')).toHaveCSS('visibility', 'visible', { timeout: 30000 });
          const sample = await page.evaluate(async () => {
            await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
            const value = JSON.parse(sessionStorage.getItem('poietra-import-measurement'));
            if (!value?.beforeNavigationMs) throw new Error('Missing file-change/pagehide measurement');
            return { ...value, readyMs: performance.timeOrigin + performance.now() - value.start };
          });
          // Geometry and every Composition must survive the real room handoff.
          await page.getByRole('button', { name: `Composition ${compositions - 1}`, exact: true }).click();
          await expect(page.getByTestId('stage-main').locator('[data-object-id="o0"]')).toHaveAttribute('transform', `translate(${25 + compositions - 1} 25) rotate(0)`);
          if (run >= 0) samples.push(sample);
        } finally { await page.close(); }
      }
    } finally { await context.close(); }
    results.push({ objects, compositions, jsonBytes: buffer.length, updateMessageBytes, inputSha256: createHash('sha256').update(buffer).digest('hex'),
      readyMs: stats(samples.map(value => value.readyMs)), beforeNavigationMs: stats(samples.map(value => value.beforeNavigationMs)), samples });
  }
  await mkdir(dirname(output), { recursive: true });
  await writeFile(output, JSON.stringify({ measuredAt: new Date().toISOString(), environment: measuredEnvironment, browser: browser.version(), gpu,
    harnessSha256: createHash('sha256').update(await readFile(new URL(import.meta.url))).digest('hex'),
    scope: 'Production editor, one warmup then three measured file openings per case in one browser context. Capture-phase file change starts timing; destination Live status, all object nodes and visible Canvas plus two rAF opportunities end it. Includes file reading, validation, lazy services, snapshots, Yjs serialization, local durable room acknowledgment, navigation and initial rendering. Fixture creation is outside timing. No assets, decoders, WAN or physical GPU completion. Pagehide marks the pre-navigation portion; source-page rAF intervals are diagnostic only. Every sample verifies final Composition geometry after timing.', results }, null, 2) + '\n');
  console.log(JSON.stringify(results.map(({ samples, ...result }) => result), null, 2));
} finally { await browser.close(); }
