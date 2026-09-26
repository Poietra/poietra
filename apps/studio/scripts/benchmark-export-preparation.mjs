// Capture + timeline preparation through the browser-capability boundary.
// Intentionally runs without browser globals: no codec, rasterizer or I/O starts.
import assert from 'node:assert/strict';
import { performance } from 'node:perf_hooks';
import { readFileSync } from 'node:fs';
import { defaultState } from '../shared/model.js';
import { exportProject, exportScene } from '../src/engine/export.js';

const kernel = (await WebAssembly.instantiate(readFileSync(new URL('../public/wasm/poietra_core.wasm', import.meta.url)))).instance.exports;
const originalClone = globalThis.structuredClone;
let clones = 0, sourceClones = 0;
globalThis.structuredClone = (...args) => {
  clones++;
  const value = args[0];
  if (value?.sceneOrder && value?.scenes || value?.compositionOrder && value?.objects) sourceClones++;
  return originalClone(...args);
};
const median = values => [...values].sort((a, b) => a - b)[values.length >> 1];
function scene(id, compositions) {
  const scene = { id, name: id, width: 1280, height: 720, background: '#000000', objects: {}, compositions: {}, compositionOrder: [], transitions: {}, audioTracks: {} };
  for (let i = 0; i < 500; i++) scene.objects[`o${i}`] = { id: `o${i}`, name: `Object ${i}`, kind: 'circle', order: i, locked: false, groupId: null };
  for (let c = 0; c < compositions; c++) {
    const cid = `c${c}`; scene.compositionOrder.push(cid);
    scene.compositions[cid] = { id: cid, name: cid, duration: 1000, states: {} };
    for (let i = 0; i < 500; i++) scene.compositions[cid].states[`o${i}`] = defaultState('circle', { x: i % 25 * 48 + c, y: Math.floor(i / 25) * 32 });
    if (c) scene.transitions[`t${c}`] = { id: `t${c}`, fromId: `c${c - 1}`, toId: cid, duration: 500, tracks: {} };
  }
  return scene;
}
const results = [];
try {
  for (const compositions of [2, 12]) for (const scenes of [1, 2]) {
    const a = scene('a', compositions), b = scene('b', compositions);
    const project = { version: 1, name: 'Export benchmark', sceneOrder: ['a', 'b'], scenes: { a, b } };
    const run = async () => {
      try {
        await (scenes === 1 ? exportScene(a, kernel, { format: 'webm', fps: 30 }) : exportProject(project, kernel, { format: 'webm', fps: 30 }));
        assert.fail('Expected the missing-browser boundary.');
      } catch (error) { assert.match(error.message, /WebCodecs/); }
    };
    const batch = async () => { const start = performance.now(); for (let i = 0; i < 5; i++) await run(); return (performance.now() - start) / 5; };
    await batch(); await batch();
    const samples = []; clones = 0; sourceClones = 0;
    for (let batchIndex = 0; batchIndex < 7; batchIndex++) samples.push(await batch());
    results.push({ scenes, compositionsPerScene: compositions, objectsPerScene: 500, clonesPerExport: clones / 35, sourceClonesPerExport: sourceClones / 35,
      msPerPreparation: median(samples), samples: { msPerPreparation: samples } });
  }
} finally { globalThis.structuredClone = originalClone; }
console.log(JSON.stringify({ scope: 'Public browser export capture + compiled timeline preparation through the missing-WebCodecs environment check, using real WASM. No UI/dialog, painting, encoding, media, I/O or asynchronous codec loading. Counts native structuredClone calls; not end-to-end export duration or allocated bytes.', iterations: '2 warmup + 7 measured batches of 5 preparations, 500 objects per Scene', results }, null, 2));
