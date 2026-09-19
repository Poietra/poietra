import { performance } from 'node:perf_hooks';
import * as Y from 'yjs';
import { defaultState, type Project, type Scene } from '../shared/model.js';
import { initializeDocument, readProject, getShared } from '../shared/document.js';

function fixture(count: number): Project {
  const scenes: Record<string, Scene> = {};
  for (let index = 0; index < 3; index++) {
    const scene: Scene = { id: `s${index}`, name: 'Scene', width: 1280, height: 720, background: '#000000', objects: {}, compositions: {}, compositionOrder: [], transitions: {} };
    for (let i = 0; i < count; i++) scene.objects[`o${i}`] = { id: `o${i}`, kind: 'circle', name: 'Circle', order: i, locked: false, groupId: null };
    for (let i = 0; i < 5; i++) {
      const id = `c${i}`;
      scene.compositionOrder.push(id);
      scene.compositions[id] = { id, name: id, duration: 1000, accent: '#ffffff', states: Object.fromEntries(Object.keys(scene.objects).map(key => [key, defaultState('circle')])) };
    }
    scenes[scene.id] = scene;
  }
  return { version: 1, name: 'Snapshot benchmark', sceneOrder: Object.keys(scenes), scenes };
}
const median = (values: number[]) => [...values].sort((a, b) => a - b)[values.length >> 1];
const results: object[] = [];
let checksum = 0;
for (const count of [100, 500]) {
  const source = fixture(count);
  const doc = new Y.Doc();
  initializeDocument(doc, source);
  const state = getShared(doc, ['scenes', 's0', 'compositions', 'c0', 'states', 'o0']) as Y.Map<unknown>;
  const measure = () => {
    const start = performance.now();
    for (let i = 0; i < 50; i++) { state.set('x', i); checksum += readProject(doc)!.scenes.s0.compositions.c0.states.o0.x; }
    return (performance.now() - start) / 50;
  };
  readProject(doc); measure();
  const samples = Array.from({ length: 7 }, measure);
  results.push({ scenes: 3, compositionsPerScene: 5, objectsPerScene: count, msPerEditAndRead: median(samples), samples: { msPerEditAndRead: samples } });
  doc.destroy();
}
console.log(JSON.stringify({ scope: 'One Yjs leaf edit and a complete MoonBit project snapshot; excludes UI/rendering/network', iterations: '7 batches × 50 edits after warmup', results, checksum }, null, 2));
