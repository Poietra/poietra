import { readFileSync } from 'node:fs';
import { performance } from 'node:perf_hooks';
import { makeDemoProject } from '../shared/demo';
import { defaultTrack } from '../shared/model';
import { compileScene } from '../src/engine/evaluate';
import { evaluateScene as original } from '../tests/oracle/evaluate';
import type { MotionKernel } from '../src/engine/kernel';

const rust = (await WebAssembly.instantiate(readFileSync(new URL('../tests/oracle/rust-motion.wasm', import.meta.url)))).instance.exports as unknown as MotionKernel;
const moon = (await WebAssembly.instantiate(readFileSync(new URL('../public/wasm/poietra_core.wasm', import.meta.url)))).instance.exports as unknown as MotionKernel;
const median = (values: number[]) => [...values].sort((a, b) => a - b)[Math.floor(values.length / 2)];
const results = [];
let checksum = 0;
for (const easing of ['preset', 'custom']) for (const count of [10, 100, 500]) {
  const scene = makeDemoProject().scenes['scene-1'];
  const object = scene.objects.circle, a = scene.compositions['comp-1'].states.circle, b = scene.compositions['comp-2'].states.circle;
  scene.objects = {}; scene.compositions['comp-1'].states = {}; scene.compositions['comp-2'].states = {};
  const transition = scene.transitions['transition-1']; transition.tracks = {};
  for (let i = 0; i < count; i++) {
    const id = `object-${i}`;
    scene.objects[id] = { ...object, id, order: i };
    scene.compositions['comp-1'].states[id] = { ...a, x: i * 4, y: i % 10 * 10 };
    scene.compositions['comp-2'].states[id] = { ...b, x: i * 4 + 100, y: i % 10 * 10 + 100, fill: '#123456' };
    transition.tracks[id] = defaultTrack(id, { duration: 800, easing: easing === 'preset' ? 'easeInOut' : { type: 'cubicBezier', x1: .25, y1: .1, x2: .25, y2: 1 } });
  }
  const preparations: number[] = [];
  for (let i = 0; i < 7; i++) { const start = performance.now(); compileScene(scene, moon); preparations.push(performance.now() - start); }
  const program = compileScene(scene, moon);
  const run = (fn: (time: number) => ReturnType<typeof original>) => {
    const start = performance.now();
    for (let frame = 0; frame < 240; frame++) { const value = fn(1000 + frame % 48 / 60 * 1000); checksum += value.objects[0].state.x; }
    return (performance.now() - start) / 240;
  };
  const old = (time: number) => original(scene, time, rust);
  run(old); run(program.evaluate);
  const originalTimes: number[] = [], preparedTimes: number[] = [];
  for (let round = 0; round < 7; round++) {
    if (round % 2) { preparedTimes.push(run(program.evaluate)); originalTimes.push(run(old)); }
    else { originalTimes.push(run(old)); preparedTimes.push(run(program.evaluate)); }
  }
  results.push({ easing, objects: count, prepareMs: median(preparations), originalMsPerFrame: median(originalTimes), moonbitMsPerFrame: median(preparedTimes), speedup: median(originalTimes) / median(preparedTimes) });
}
console.log(JSON.stringify({ runtime: process.version, platform: `${process.platform}/${process.arch}`, measurement: 'CPU scene evaluation only; excludes rendering, encoding and browser display', iterations: '7 alternating batches × 240 frames after warmup', results, checksum }, null, 2));
