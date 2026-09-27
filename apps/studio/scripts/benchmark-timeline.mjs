// Public timeline projections: geometry and media payloads are outside their needs.
import assert from 'node:assert/strict';
import { makeBlankScene } from '../shared/demo.js';
import { defaultState, sceneDuration, sceneSegments } from '../shared/model.js';

const results = []; let checksum = 0;
for (const objects of [100, 500]) for (const compositions of [2, 12]) for (const media of [false, true]) {
  const scene = makeBlankScene('scene', 'Timeline'); scene.compositions = {}; scene.compositionOrder = []; scene.transitions = {}; scene.objects = {};
  for (let i = 0; i < objects; i++) {
    const video = media && i % 10 === 0;
    scene.objects[`o${i}`] = { id: `o${i}`, name: `Object ${i}`, kind: video ? 'video' : 'circle', order: i, locked: false, groupId: null,
      ...(video ? { media: { src: '/api/rooms/' + 'a'.repeat(32) + '/media/' + 'b'.repeat(64), mime: 'video/mp4', duration: 30000, hasAudio: false, width: 640, height: 360, waveform: [] }, playback: { start: 0, offset: 0, duration: 30000 } } : {}) };
  }
  for (let c = 0; c < compositions; c++) {
    const id = `c${c}`; scene.compositionOrder.push(id);
    scene.compositions[id] = { id, name: id, accent: '#123456', duration: 1000, states: Object.fromEntries(Object.entries(scene.objects).map(([id, object]) => [id, defaultState(object.kind, { visible: object.kind !== 'video' || c === compositions - 1 })])) };
    if (c) scene.transitions[`t${c}`] = { id: `t${c}`, fromId: `c${c-1}`, toId: id, duration: 250, tracks: {} };
  }
  if (media) scene.audioTracks = { audio: { id: 'audio', name: 'Audio', asset: { src: '/api/rooms/' + 'a'.repeat(32) + '/media/' + 'c'.repeat(64), mime: 'audio/wav', duration: 35000, hasAudio: true, waveform: [] }, start: 0, offset: 0, duration: 35000, volume: 1, muted: false } };
  const visualDuration = compositions * 1000 + (compositions - 1) * 250;
  const parts = sceneSegments(scene); assert.equal(parts.length, compositions * 2 - 1); assert.equal(parts.at(-1).start + parts.at(-1).duration, visualDuration);
  assert.equal(sceneDuration(scene), media ? 35000 : visualDuration);
  for (const operation of ['segments', 'duration']) {
    const run = operation === 'segments' ? () => sceneSegments(scene).length : () => sceneDuration(scene);
    const iterations = 1000;
    const batch = () => { const start = performance.now(); for (let i = 0; i < iterations; i++) checksum += run(); return (performance.now() - start) / iterations; };
    batch(); batch(); const samples = Array.from({ length: 7 }, batch);
    results.push({ operation, objects, compositions, media, iterations, msPerOperation: [...samples].sort((a,b) => a-b)[3], samples: { msPerOperation: samples } });
  }
}
console.log(JSON.stringify({ scope: 'Public Scene timeline segments and duration. Media cases have one video per ten objects visible only in the final Composition, plus an independent audio track. Sources are room references. Reads are repeated against a stable ordinary caller-owned Scene, without a cache. No frame evaluation, Yjs, UI, browser, media decoding or I/O.', iterations: 'Two warmup + seven measured batches of 1000 calls in each fresh process', results, checksum }, null, 2));
