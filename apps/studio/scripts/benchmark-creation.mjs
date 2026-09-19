import assert from 'node:assert/strict';
import { performance } from 'node:perf_hooks';
import * as Y from 'yjs';
import { makeBlankScene } from '../shared/demo.js';
import { defaultState } from '../shared/model.js';
import { initializeDocument, readProject } from '../shared/document.js';
import { EditorStore } from '../src/editor/store.js';
import { EditorUndoManager } from '../src/editor/undo.js';

const median = values => [...values].sort((a, b) => a - b)[values.length >> 1];
const results = [];
let checksum = 0;
for (const count of [0, 100, 500]) {
  const scene = makeBlankScene('s', 'Scene');
  const cid = scene.compositionOrder[0];
  for (let i = 0; i < count; i++) {
    const id = `o${i}`;
    scene.objects[id] = { id, name: id, kind: 'circle', order: i, locked: false, groupId: null };
    scene.compositions[cid].states[id] = defaultState('circle', { x: i });
  }
  const seed = new Y.Doc();
  initializeDocument(seed, { version: 1, name: 'Creation', sceneOrder: ['s'], scenes: { s: scene } });
  const update = Y.encodeStateAsUpdate(seed); seed.destroy();
  const run = verify => {
    const doc = new Y.Doc(); Y.applyUpdate(doc, update);
    const undoManager = new EditorUndoManager(doc);
    const store = Object.assign(Object.create(EditorStore.prototype), { doc, undoManager });
    // Materialize the existing immutable snapshot outside the timed command.
    store.scene('s');
    try {
      const start = performance.now();
      const id = store.addComposition('s');
      const elapsed = performance.now() - start;
      const current = readProject(doc).scenes.s;
      checksum += Object.keys(current.compositions[id].states).length;
      if (verify) {
        assert.deepEqual(current.compositions[id].states, scene.compositions[cid].states);
        assert.deepEqual(current.compositionOrder, [cid, id]);
        const transition = Object.values(current.transitions)[0];
        assert.equal(Object.keys(transition.tracks).length, count);
        assert.equal(transition.duration, 800);
        assert(Object.values(transition.tracks).every(track => track.implicit));
        assert.equal(undoManager.undoStack.length, 1);
      }
      return elapsed;
    } finally { undoManager.destroy(); doc.destroy(); }
  };
  run(true);
  const batch = () => {
    let elapsed = 0;
    for (let i = 0; i < 5; i++) elapsed += run(false);
    return elapsed / 5;
  };
  batch(); batch();
  const samples = Array.from({ length: 7 }, batch);
  results.push({ operation: 'append composition', objects: count, msPerOperation: median(samples), samples: { msPerOperation: samples } });
}
console.log(JSON.stringify({ scope: 'Composition creation including snapshot reuse, IDs, JS marshalling, local Yjs publication and Undo capture; excludes fixture setup, cleanup, UI, rendering, persistence and networking', iterations: '7 batches × 5 fresh documents after 2 warmup batches; one creation per document', results, checksum }, null, 2));
