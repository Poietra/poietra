import assert from 'node:assert/strict';
import { performance } from 'node:perf_hooks';
import { defaultTrack, PROPERTY_CHANNELS } from '../shared/model.js';
import { setTransitionDuration } from '../../../_build/js/release/build/browser_editor/browser_editor.js';

const results = [];
let checksum = 0;
const median = values => [...values].sort((a, b) => a - b)[values.length >> 1];
for (const count of [100, 500]) for (const operation of ['extend', 'shorten base', 'shorten properties', 'locked floor']) {
  const ids = Array.from({ length: count }, (_, i) => `o${i}`);
  const properties = operation === 'shorten properties';
  const tracks = Object.fromEntries(ids.map(id => [id, defaultTrack(id, {
    start: 100, duration: 700, implicit: properties,
    ...(properties ? Object.fromEntries(PROPERTY_CHANNELS.map(channel => [`${channel}Timing`, { start: 100, duration: 700, easing: 'linear' }])) : {}),
  })]));
  const objects = Object.fromEntries(ids.map(id => [id, { id, locked: operation === 'locked floor' && id === 'o0' }]));
  const scene = { objects, transitions: { t: { duration: 800, tracks } } };
  let changes;
  const store = { scene: () => scene, edit: value => { changes = value; } };
  const requested = operation === 'extend' ? 1000 : 500;
  const run = () => {
    setTransitionDuration(store, 's', 't', requested);
    // Consume numeric output even when unchanged leaves have been elided.
    checksum += changes[0].value;
  };
  run();
  assert.deepEqual(changes[0], { path: ['scenes', 's', 'transitions', 't', 'duration'], value: operation === 'locked floor' ? 800 : requested });
  const applied = structuredClone(scene.transitions.t);
  for (const { path, value } of changes) {
    let node = applied;
    for (const key of path.slice(4, -1)) node = node[key];
    node[path.at(-1)] = value;
  }
  assert.equal(applied.tracks.o0.start, 100);
  assert.equal(applied.tracks.o0.duration, operation === 'shorten base' ? 400 : 700);
  if (properties) for (const channel of PROPERTY_CHANNELS) assert.deepEqual(applied.tracks.o0[`${channel}Timing`], { start: 100, duration: 400, easing: 'linear' });
  const batch = () => {
    const start = performance.now();
    for (let i = 0; i < 100; i++) run();
    return (performance.now() - start) / 100;
  };
  batch(); batch();
  const samples = Array.from({ length: 7 }, batch);
  results.push({ operation, tracks: count, overridesPerTrack: properties ? 11 : 0, msPerOperation: median(samples), samples: { msPerOperation: samples } });
}
console.log(JSON.stringify({ scope: 'Transition duration planning and JS marshalling; excludes Yjs publication, UI, rendering and networking', iterations: '7 batches × 100 operations after 2 warmup batches', results, checksum }, null, 2));
