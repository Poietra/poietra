import assert from 'node:assert/strict';
import { performance } from 'node:perf_hooks';
import { editableGroupMembers } from '../src/editor/groups.js';
import { translate } from '../../../_build/js/release/build/browser_editor/browser_editor.js';

const median = values => [...values].sort((a, b) => a - b)[values.length >> 1];
const results = [];
let checksum = 0;
function measure(operation, dimensions, run) {
  const batch = () => {
    const start = performance.now();
    for (let i = 0; i < 200; i++) run();
    return (performance.now() - start) / 200;
  };
  batch(); batch();
  const samples = Array.from({ length: 7 }, batch);
  results.push({ operation, ...dimensions, msPerOperation: median(samples), samples: { msPerOperation: samples } });
}
for (const count of [100, 500]) {
  const ids = Array.from({ length: count }, (_, i) => `o${i}`);
  const objects = Object.fromEntries(ids.map((id, i) => [id, { id, groupId: `g${i >> 2}`, locked: false, order: i }]));
  const states = Object.fromEntries(ids.map(id => [id, { x: 10, y: 20 }]));
  const scene = { id: 's', objects, compositions: { c: { states } } };
  for (const selected of [1, 50, count]) {
    const selection = ids.slice(0, selected);
    const expected = ids.slice(0, Math.min(count, Math.ceil(selected / 4) * 4)).map(id => objects[id]);
    const result = editableGroupMembers(scene, selection);
    assert.deepEqual(result, expected);
    assert.equal(result[0], objects.o0);
    measure('expand groups', { objects: count, selected }, () => { checksum += editableGroupMembers(scene, selection).length; });
  }
  // Isolate planning + JS marshalling. Real Yjs publication is covered separately.
  let changes;
  const store = { scene: () => scene, edit: values => { changes = values; checksum += values.length; } };
  translate(store, 's', 'c', states, 1.25, -2.25);
  assert.equal(changes.length, count * 2);
  assert.deepEqual(changes[0], { path: ['scenes', 's', 'compositions', 'c', 'states', 'o0', 'x'], value: 11.3 });
  assert.deepEqual(changes[1], { path: ['scenes', 's', 'compositions', 'c', 'states', 'o0', 'y'], value: 17.8 });
  measure('plan drag', { objects: count, selected: count }, () => { translate(store, 's', 'c', states, 1.25, -2.25); });
}
console.log(JSON.stringify({ scope: 'Public MoonBit group selection and drag planning, including JS marshalling; excludes Yjs publication, UI, rendering and network', iterations: '7 batches × 200 operations after 2 warmup batches', results, checksum }, null, 2));
