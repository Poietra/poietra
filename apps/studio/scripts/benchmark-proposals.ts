import { performance } from 'node:perf_hooks';
import assert from 'node:assert/strict';
import * as Y from 'yjs';
import { defaultState, type Project, type Scene } from '../shared/model.js';
import { initializeDocument, readProject } from '../shared/document.js';
import { compileProposal } from '../shared/ai.js';
import { compileProposal as original } from '../tests/oracle/ai-compiler.ts';

const median = (values: number[]) => [...values].sort((a, b) => a - b)[values.length >> 1];
const results: object[] = [];
let checksum = 0;
for (const [objects, compositions] of [[100, 10], [500, 10], [500, 40]]) {
  const scene: Scene = { id: 'scene', name: 'Scene', width: 1280, height: 720, background: '#000000', objects: {}, compositions: {}, compositionOrder: [], transitions: {} };
  for (let index = 0; index < objects; index++) {
    const id = `o${index}`;
    scene.objects[id] = { id, name: id, kind: 'circle', order: index, locked: false, groupId: null };
  }
  for (let index = 0; index < compositions; index++) {
    const id = `c${index}`;
    scene.compositionOrder.push(id);
    scene.compositions[id] = { id, name: id, duration: 1000, accent: '#ffffff', states: Object.fromEntries(Object.keys(scene.objects).map(id => [id, defaultState('circle')])) };
  }
  const project: Project = { version: 1, name: 'Compiler benchmark', sceneOrder: ['scene'], scenes: { scene } };
  const doc = new Y.Doc(); initializeDocument(doc, project);
  const source = readProject(doc)!;
  const raw = { message: 'One field', operations: [{ action: 'setState' as const, compositionId: 'c0', objectId: 'o0', property: 'x' as const, value: 321 }] };
  const before = original(doc, source, 'scene', raw), after = compileProposal(doc, source, 'scene', raw);
  assert.deepEqual(after.changes, before.changes); assert.deepEqual(after.guards, before.guards);
  const measure = (compile: typeof compileProposal) => {
    const start = performance.now();
    for (let i = 0; i < 10; i++) checksum += compile(doc, source, 'scene', raw).changes.length;
    return (performance.now() - start) / 10;
  };
  measure(original); measure(compileProposal);
  const previous: number[] = [], moonbit: number[] = [];
  for (let batch = 0; batch < 7; batch++) {
    if (batch % 2) { moonbit.push(measure(compileProposal)); previous.push(measure(original)); }
    else { previous.push(measure(original)); moonbit.push(measure(compileProposal)); }
  }
  results.push({ objects, compositions, originalMs: median(previous), moonbitMs: median(moonbit), speedup: median(previous) / median(moonbit), samples: { originalMs: previous, moonbitMs: moonbit } });
  doc.destroy();
}
console.log(JSON.stringify({ scope: 'One-field AI proposal compilation including guards/preflight, from an already-read immutable project; excludes model/network/UI/application', iterations: '7 alternating batches × 10 compilations after warmup', node: process.version, results, checksum }, null, 2));
