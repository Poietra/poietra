// CPU evaluation and one parent edit; no rendering, browser or network timing.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { performance } from 'node:perf_hooks';
import * as Y from 'yjs';
import { makeDemoProject } from '../shared/demo.js';
import { defaultState, defaultTrack } from '../shared/model.js';
import { initializeDocument, readProject } from '../shared/document.js';
import { compileScene, compositionFrame } from '../src/engine/evaluate.js';
import { EditorStore } from '../src/editor/store.js';
import { EditorUndoManager } from '../src/editor/undo.js';

const kernel = (await WebAssembly.instantiate(readFileSync(new URL('../public/wasm/poietra_core.wasm', import.meta.url)))).instance.exports;
const median = values => [...values].sort((a, b) => a - b)[values.length >> 1];
const results = []; let checksum = 0;
function measure(fn, iterations) {
  const batch = () => { const start = performance.now(); for (let index = 0; index < iterations; index++) fn(index); return (performance.now() - start) / iterations; };
  batch(); batch(); const samples = Array.from({ length: 7 }, batch);
  return { median: median(samples), samples };
}
for (const count of [100, 500]) for (const variant of ['flat', 'hierarchy', 'hierarchy + 6 points/object']) {
  const project = makeDemoProject(), scene = project.scenes['scene-1'];
  scene.objects = {}; for (const composition of Object.values(scene.compositions)) composition.states = {};
  const transition = scene.transitions['transition-1']; transition.tracks = {}; transition.duration = 800;
  for (let index = 0; index < count; index++) {
    const id = `o${index}`;
    scene.objects[id] = { id, name: id, order: index, kind: 'rectangle', groupId: null, locked: false, ...(variant !== 'flat' && index > 0 ? { parentId: 'o0' } : {}) };
    for (const [position, composition] of Object.values(scene.compositions).entries()) {
      composition.states[id] = defaultState('rectangle', { x: index % 25 * 25 + 100 * position, y: Math.floor(index / 25) * 25, width: 18, height: 18, visible: true, fill: '#6699aa', ...(index === 0 && variant !== 'flat' ? { rotation: 25 + 10 * position, scaleX: 1.5, scaleY: .8 } : {}) });
    }
    transition.tracks[id] = defaultTrack(id, { duration: 800, easing: 'linear', keyframes: variant.includes('points') ? Object.fromEntries(Array.from({ length: 6 }, (_, key) => [`k${key}`, { property: key % 2 ? 'opacity' : 'x', at: (Math.floor(key / 2) + 1) / 4, value: key % 2 ? .4 + .1 * key : index % 25 * 25 + 70, easing: 'easeInOut' }])) : {} });
  }
  const preparation = measure(() => { compileScene(scene, kernel); checksum += 1; }, 20);
  const program = compileScene(scene, kernel);
  const evaluation = measure(index => { const frame = program.transition('transition-1', index % 48 / 60 * 1000); checksum += frame.objects.at(-1).state.x; assert.equal(frame.objects.length, count); }, 240);
  let editAndFrame = null;
  if (variant !== 'flat') {
    const doc = new Y.Doc(); initializeDocument(doc, project);
    const store = Object.assign(Object.create(EditorStore.prototype), { doc, undoManager: new EditorUndoManager(doc) });
    const before = store.scene('scene-1').compositions['comp-1'].states.o1;
    let next = 0;
    editAndFrame = measure(() => {
      store.updateState('scene-1', 'comp-1', 'o0', { x: next++ % 100 });
      const current = readProject(doc).scenes['scene-1'];
      assert.equal(current.compositions['comp-1'].states.o1, before);
      const frame = compositionFrame(current, current.compositions['comp-1']);
      checksum += frame.objects[1].world.e;
    }, 100);
    doc.destroy();
  }
  results.push({ objects: count, variant, prepareMs: preparation.median, msPerFrame: evaluation.median, parentEditAndFrameMs: editAndFrame?.median ?? 0, samples: { prepareMs: preparation.samples, msPerFrame: evaluation.samples, parentEditAndFrameMs: editAndFrame?.samples ?? [] } });
}
assert(Number.isFinite(checksum));
console.log(JSON.stringify({ scope: 'Prepared transition evaluation (includes JS representation output), preparation, and parent coordinate edit + real Yjs snapshot/Undo + current Composition frame. No DOM, painting, encoding or network. Every child snapshot must retain identity after the parent edit.', iterations: '2 warmup + 7 measured batches: 20 preparations, 240 frames or 100 edits per batch', results, checksum }, null, 2));
