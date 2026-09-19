import assert from 'node:assert/strict';
import { performance } from 'node:perf_hooks';
import { defaultTrack, PROPERTY_CHANNELS } from '../shared/model.js';
import { setTrack } from '../../../_build/js/release/build/browser_editor/browser_editor.js';

const results = [];
let checksum = 0;
const median = values => [...values].sort((a, b) => a - b)[values.length >> 1];
for (const operation of ['existing duration', 'automatic activation', 'existing curve', 'property duration']) {
  const track = defaultTrack('o', {
    start: 0, duration: 600, implicit: operation === 'automatic activation',
    ...(operation === 'property duration' ? Object.fromEntries(PROPERTY_CHANNELS.map(channel => [`${channel}Timing`, { start: 100, duration: 500, easing: 'linear' }])) : {}),
  });
  const patch = operation === 'existing curve' ? { easing: { type: 'cubicBezier', x1: .2, y1: .1, x2: .7, y2: .9 } }
    : operation === 'property duration' ? { opacityTiming: { start: 100, duration: 400, easing: 'linear' } }
    : { duration: 500 };
  const scene = { objects: { o: { locked: false } }, transitions: { t: { duration: 800, tracks: { o: track } } } };
  let changes;
  const store = { scene: () => scene, edit: value => { changes = value; } };
  const run = () => {
    setTrack(store, 's', 't', 'o', patch, true);
    checksum += changes[0].path.length;
  };
  run();
  const applied = structuredClone(track);
  for (const { path, value } of changes) {
    let node = applied;
    for (const key of path.slice(6, -1)) node = node[key];
    node[path.at(-1)] = value;
  }
  assert.deepEqual(applied, { ...track, ...patch, ...(track.implicit ? { start: 0, implicit: false } : {}) });
  const batch = () => {
    const start = performance.now();
    for (let i = 0; i < 10000; i++) run();
    return (performance.now() - start) / 10000;
  };
  batch(); batch();
  const samples = Array.from({ length: 7 }, batch);
  results.push({ operation, overrides: operation === 'property duration' ? 11 : 0, msPerOperation: median(samples), samples: { msPerOperation: samples } });
}
console.log(JSON.stringify({ scope: 'Single-track planning and JS marshalling; excludes Yjs publication, UI, rendering and networking', iterations: '7 batches × 10000 operations after 2 warmup batches', results, checksum }, null, 2));
