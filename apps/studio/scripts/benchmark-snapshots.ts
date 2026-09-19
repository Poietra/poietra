import { performance } from 'node:perf_hooks';
import * as Y from 'yjs';
import { defaultState, type Project, type Scene } from '../shared/model';
import { initializeDocument, readProject, getShared } from '../shared/document';
import { projectStructureView as originalView } from '../tests/oracle/structure-view';

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
  const legacy = new Y.Doc(), moonbit = new Y.Doc();
  initializeDocument(legacy, source); initializeDocument(moonbit, source);
  const readLegacy = () => originalView(legacy.getMap('project').toJSON() as Project);
  const readMoonbit = () => readProject(moonbit)!;
  const target = (doc: Y.Doc) => getShared(doc, ['scenes', 's0', 'compositions', 'c0', 'states', 'o0']) as Y.Map<unknown>;
  const oldTarget = target(legacy), newTarget = target(moonbit);
  const measure = (state: Y.Map<unknown>, read: () => Project) => {
    const start = performance.now();
    for (let i = 0; i < 50; i++) { state.set('x', i); checksum += read().scenes.s0.compositions.c0.states.o0.x; }
    return (performance.now() - start) / 50;
  };
  readMoonbit(); measure(oldTarget, readLegacy); measure(newTarget, readMoonbit);
  const before: number[] = [], after: number[] = [];
  for (let i = 0; i < 7; i++) {
    if (i % 2) { after.push(measure(newTarget, readMoonbit)); before.push(measure(oldTarget, readLegacy)); }
    else { before.push(measure(oldTarget, readLegacy)); after.push(measure(newTarget, readMoonbit)); }
  }
  results.push({ scenes: 3, compositionsPerScene: 5, objectsPerScene: count, originalMsPerEditAndRead: median(before), moonbitMsPerEditAndRead: median(after), speedup: median(before) / median(after), samples: { originalMsPerEditAndRead: before, moonbitMsPerEditAndRead: after } });
  legacy.destroy(); moonbit.destroy();
}
console.log(JSON.stringify({ scope: 'One Yjs leaf edit and a complete project snapshot; excludes UI/rendering/network', iterations: '7 alternating batches × 50 edits after warmup', results, checksum }, null, 2));
