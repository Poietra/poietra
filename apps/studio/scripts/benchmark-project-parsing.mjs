// Full portable parsing against a JSON-only control; input construction is untimed.
import assert from 'node:assert/strict';
import { makeBlankScene } from '../shared/demo.js';
import { defaultState } from '../shared/model.js';
import { parseProjectFile } from '../shared/project-file.js';
import { inspectProjectFile } from '../../../_build/js/release/build/headless_render/headless_render.js';

const results = []; let checksum = 0;
for (const [objects, compositions, unknownFields] of [[100, 2, false], [500, 12, false], [500, 12, true], [500, 100, false]]) {
  const scene = makeBlankScene('scene', 'Parsing');
  scene.objects = {}; scene.compositions = {}; scene.compositionOrder = []; scene.transitions = {};
  for (let i = 0; i < objects; i++) scene.objects[`o${i}`] = { id: `o${i}`, name: `Object ${i}`, kind: 'circle', order: i, locked: false, groupId: null };
  for (let c = 0; c < compositions; c++) {
    const id = `c${c}`; scene.compositionOrder.push(id);
    scene.compositions[id] = { id, name: id, accent: '#123456', duration: 1000,
      states: Object.fromEntries(Object.keys(scene.objects).map((id, i) => [id, defaultState('circle', { x: i + c, y: i * 2, text: '日本語😀' })])) };
    if (c) scene.transitions[`t${c}`] = { id: `t${c}`, fromId: `c${c-1}`, toId: id, duration: 250, tracks: {} };
  }
  const expected = { version: 1, name: 'Parsing', sceneOrder: [scene.id], scenes: { [scene.id]: scene } };
  const input = structuredClone(expected);
  if (unknownFields) {
    input.extra = { ignored: ['日本語', 1] };
    for (const composition of Object.values(input.scenes.scene.compositions)) for (const state of Object.values(composition.states)) {
      state.extra = { ignored: ['payload', 1] }; state.path.c1.extra = true;
    }
  }
  const text = JSON.stringify(input), iterations = compositions === 100 ? 1 : 3;
  assert.deepEqual(parseProjectFile(text), expected);
  const inspection = inspectProjectFile(text);
  assert.equal(inspection.scenes, 1);
  assert.equal(inspection.durationMs, compositions * 1000 + (compositions - 1) * 250);
  for (const operation of ['json', 'portable', 'headless-inspect']) {
    const run = operation === 'json' ? () => JSON.parse(text).sceneOrder.length
      : operation === 'portable' ? () => parseProjectFile(text).sceneOrder.length : () => inspectProjectFile(text).scenes;
    const batch = () => { const start = performance.now(); for (let i = 0; i < iterations; i++) checksum += run(); return (performance.now() - start) / iterations; };
    batch(); batch(); const samples = Array.from({ length: 7 }, batch);
    results.push({ objects, compositions, unknownFields, operation, jsonBytes: Buffer.byteLength(text), iterations,
      msPerOperation: [...samples].sort((a, b) => a - b)[3], samples: { msPerOperation: samples } });
  }
}
console.log(JSON.stringify({ scope: 'One Scene, shape poses across 2/12/100 Compositions. Full portable parsing includes bounded UTF-8 checking, reserved-key validation, schema normalization and reference validation. Headless inspection additionally prepares the render timeline, without rasterization, codecs or I/O. JSON.parse is a control only and performs no validation. Input creation, stringify and assertions are outside timing. No browser or peak-memory measurement.', iterations: 'Two warmup + seven measured batches, with per-case iteration counts; each process constructs identical input.', results, checksum }, null, 2));
