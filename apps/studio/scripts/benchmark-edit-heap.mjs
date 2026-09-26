// Build first. Retained editing-view heap, with the shared documents kept alive.
import { execFileSync } from 'node:child_process';
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';
import { environment, stats } from './benchmark-environment.mjs';

const { values } = parseArgs({ options: {
  output: { type: 'string', default: 'test-results/benchmarks/edit-heap.json' },
  runs: { type: 'string', default: '5' },
  sample: { type: 'string' },
} });
const scenarios = [100, 500];
if (values.sample !== undefined) {
  if (!global.gc) throw new Error('The sample process needs --expose-gc');
  const objects = scenarios[Number(values.sample)];
  const Y = await import('yjs');
  const { makeDemoProject } = await import('../shared/demo.js');
  const { initializeDocument, readProject, getShared } = await import('../shared/document.js');
  const { compositionFrame } = await import('../src/engine/evaluate.js');
  const project = makeDemoProject(), source = project.scenes['scene-1'];
  const object = source.objects.circle, state = source.compositions['comp-1'].states.circle;
  source.objects = {};
  source.transitions = {};
  for (const composition of Object.values(source.compositions)) composition.states = {};
  for (let index = 0; index < objects; index++) {
    const id = `o${index}`;
    source.objects[id] = { ...object, id, order: index, ...(index ? { parentId: 'o0' } : {}) };
    for (const composition of Object.values(source.compositions)) composition.states[id] = structuredClone({ ...state, x: index * 2 });
  }
  let checksum = 0;
  function frame(scene) {
    const result = compositionFrame(scene, scene.compositions['comp-1'], 0);
    if (result.objects.length !== objects) throw new Error('Missing object');
    checksum += result.objects.at(-1).world.e;
  }
  function fixture() {
    const doc = new Y.Doc();
    initializeDocument(doc, project);
    return { doc, scene: readProject(doc).scenes['scene-1'] };
  }
  function warmup() {
    const value = fixture();
    for (let index = 0; index < 20; index++) frame(value.scene);
    value.doc.destroy();
  }
  for (let index = 0; index < 3; index++) warmup();
  global.gc();
  const documents = Array.from({ length: 8 }, fixture);
  global.gc();
  const before = process.memoryUsage().heapUsed;
  for (const value of documents) frame(value.scene);
  global.gc();
  const retainedViewBytes = (process.memoryUsage().heapUsed - before) / documents.length;
  for (const value of documents) {
    const pose = getShared(value.doc, ['scenes', 'scene-1', 'compositions', 'comp-1', 'states', 'o0']);
    for (let index = 0; index < 100; index++) {
      pose.set('x', index);
      value.scene = readProject(value.doc).scenes['scene-1'];
      frame(value.scene);
    }
  }
  global.gc();
  const retainedAfterEditsBytes = (process.memoryUsage().heapUsed - before) / documents.length;
  for (const value of documents) { frame(value.scene); value.doc.destroy(); }
  console.log(JSON.stringify({ objects, retainedViewBytes, retainedAfterEditsBytes, checksum }));
} else {
  const runs = Number(values.runs);
  if (!Number.isInteger(runs) || runs < 1 || runs > 9) throw new Error('--runs must be 1..9');
  const report = { measuredAt: new Date().toISOString(), environment: environment(),
    method: 'Five sequential fresh processes by default. Three disposable warmup documents, 20 frames each. Eight live documents with two Compositions and parents; only the first Composition is rendered. JS heap delta after forced GC, relative to the native snapshot before its first frame. After-edit delta also includes Yjs and snapshot bookkeeping for 100 parent edits. Excludes transient allocation, native/WASM memory, DOM, media and Undo history.', results: [],
  };
  for (let scenario = 0; scenario < scenarios.length; scenario++) {
    const samples = [];
    for (let run = 0; run < runs; run++) {
      console.error(`edit heap ${scenarios[scenario]} objects: process ${run + 1}/${runs}`);
      samples.push(JSON.parse(execFileSync(process.execPath, ['--expose-gc', fileURLToPath(import.meta.url), '--sample', String(scenario)], { encoding: 'utf8', timeout: 120000 })));
    }
    report.results.push({ objects: scenarios[scenario], retainedViewBytes: stats(samples.map(s => s.retainedViewBytes)), retainedAfterEditsBytes: stats(samples.map(s => s.retainedAfterEditsBytes)), samples });
  }
  report.completedAt = new Date().toISOString();
  const output = resolve(values.output);
  mkdirSync(dirname(output), { recursive: true });
  writeFileSync(output, JSON.stringify(report, null, 2) + '\n');
  console.table(report.results.map(({ objects, retainedViewBytes, retainedAfterEditsBytes }) => ({ objects, retainedViewBytes: retainedViewBytes.median, retainedAfterEditsBytes: retainedAfterEditsBytes.median })));
  console.error(`Saved ${output}`);
}
