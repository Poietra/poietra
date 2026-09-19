import { readFile } from 'node:fs/promises';
import { beforeAll, expect, test } from 'vitest';
import * as jsKernel from '../../../_build/js/release/build/motion/motion.js';
import { makeDemoProject } from '../shared/demo';
import { defaultTrack, PROPERTY_CHANNELS, type AnimationKind, type Easing } from '../shared/model';
import * as original from './oracle/evaluate';
import * as migrated from '../src/engine/evaluate';
import type { MotionKernel } from '../src/engine/kernel';

let rust: MotionKernel, moon: MotionKernel;
beforeAll(async () => {
  const instantiate = async (url: URL) => (await WebAssembly.instantiate(await readFile(url))).instance.exports as unknown as MotionKernel;
  [rust, moon] = await Promise.all([
    instantiate(new URL('./oracle/rust-motion.wasm', import.meta.url)),
    instantiate(new URL('../public/wasm/poietra_core.wasm', import.meta.url)),
  ]);
});

test('MoonBit JS and WASM preserve the Rust kernel at finite and non-finite boundaries', () => {
  const samples = [-Infinity, -1, -0, 0, 0.00001, .125, .25, .49999, .5, .75, .99999, 1, 2, Infinity, NaN];
  for (const value of samples) for (const candidate of [jsKernel, moon]) {
    for (const kind of [0, 1, 2, 3, 99]) expect(candidate.ease(value, kind)).toBe(rust.ease(value, kind));
    expect(candidate.interpolate(-120, 300, value)).toBe(rust.interpolate(-120, 300, value));
    expect(candidate.cubic_bezier(-100, 35, 110, 20, value)).toBe(rust.cubic_bezier(-100, 35, 110, 20, value));
    for (const [x1, y1, x2, y2] of [[0, 0, 0, 1], [1, 0, 1, 1], [1, 0, 0, 1], [.25, .1, .25, 1], [NaN, 0, 1, 1]]) {
      expect(candidate.cubic_bezier_ease(value, x1, y1, x2, y2)).toBe(rust.cubic_bezier_ease(value, x1, y1, x2, y2));
    }
  }
});

test('the original evaluator is an oracle for every animation and independently timed channel', () => {
  const easings: Easing[] = ['linear', 'easeInOut', 'easeIn', 'easeOut', { type: 'cubicBezier', x1: .2, y1: .05, x2: .65, y2: 1 }];
  for (const type of ['move', 'write', 'fade', 'grow', 'none'] as AnimationKind[]) {
    for (const easing of easings) for (const channel of PROPERTY_CHANNELS) {
      const scene = makeDemoProject().scenes['scene-1'];
      const transition = scene.transitions['transition-1'];
      const track = transition.tracks.circle = defaultTrack('circle', { type, start: 100, duration: 600, easing,
        path: { c1: { x: 50, y: 200 }, c2: { x: 1100, y: 60 } },
        [`${channel}Timing`]: { start: 50, duration: 300, easing: 'linear' },
      });
      const a = scene.compositions['comp-1'].states.circle, b = scene.compositions['comp-2'].states.circle;
      Object.assign(a, { width: 12, height: -5, opacity: .2, fill: '#0a30FF', stroke: 'none', rotation: -130 });
      Object.assign(b, { width: 600, height: 60, opacity: .9, fill: '#fd1901', stroke: '#112233', rotation: 70 });
      for (const [fromVisible, toVisible] of [[true, true], [true, false], [false, true], [false, false]]) {
        a.visible = fromVisible; b.visible = toVisible;
        const program = migrated.compileScene(scene, moon);
        for (const time of [-1, 0, 49, 50, 100, 125, 300, 350, 500, 699, 700, 800, 1000]) {
          expect(migrated.transitionFrame(scene, transition, time, moon)).toEqual(original.transitionFrame(scene, transition, time, rust));
          expect(program.transition(transition.id, time)).toEqual(original.transitionFrame(scene, transition, time, rust));
          expect(program.evaluate(time + 1000)).toEqual(original.evaluateScene(scene, time + 1000, rust));
        }
      }
      track[`${channel}Timing`] = null;
      track.implicit = true;
      expect(migrated.transitionFrame(scene, transition, 250, moon)).toEqual(original.transitionFrame(scene, transition, 250, rust));
    }
  }
// Exhaustive semantic comparisons, not a timing benchmark; shared CI runners can exceed 5 seconds.
}, 20000);

test('scene holds, boundaries, missing states and video clocks match the original evaluator', () => {
  const scene = makeDemoProject().scenes['scene-1'];
  scene.objects.circle = { ...scene.objects.circle, kind: 'video', media: { src: '/api/rooms/abcdefghijklmnop/media/' + 'a'.repeat(64), mime: 'video/mp4', duration: 5000, width: 640, height: 360, hasAudio: true }, playback: { start: 1250, duration: 500, offset: 100 } };
  delete scene.compositions['comp-1'].states.equation;
  const program = migrated.compileScene(scene, moon);
  for (const time of [-1, 0, 999, 1000, 1249, 1250, 1400, 1749, 1750, 1800, 3400, 10000]) {
    expect(migrated.evaluateScene(scene, time, moon)).toEqual(original.evaluateScene(scene, time, rust));
    expect(migrated.compositionFrame(scene, scene.compositions['comp-1'], time)).toEqual(original.compositionFrame(scene, scene.compositions['comp-1'], time));
    expect(program.evaluate(time)).toEqual(original.evaluateScene(scene, time, rust));
  }
});

test('compiled playback owns a snapshot and replacement programs see edits', () => {
  const scene = makeDemoProject().scenes['scene-1'];
  const before = structuredClone(original.evaluateScene(scene, 1300, rust));
  const program = migrated.compileScene(scene, moon);
  scene.compositions['comp-1'].states.circle.x = 1000;
  scene.objects.circle.name = 'A changed name';
  scene.transitions['transition-1'].tracks.circle.duration = 200;
  expect(program.evaluate(1300)).toEqual(before);
  expect(migrated.compileScene(scene, moon).evaluate(1300)).toEqual(original.evaluateScene(scene, 1300, rust));
  expect(migrated.compileScene(scene, moon).evaluate(1300)).not.toEqual(before);
});

test('compiled programs retain earlier frames across seeks and zero-duration cuts', () => {
  const scene = makeDemoProject().scenes['scene-1'];
  scene.compositions['comp-1'].duration = 0;
  scene.transitions['transition-1'].duration = 0;
  const program = migrated.compileScene(scene, moon);
  const earlier = program.evaluate(-1);
  const frozen = structuredClone(earlier);
  for (const time of [0, 3000, 10, -100, 0]) expect(program.evaluate(time)).toEqual(original.evaluateScene(scene, time, rust));
  expect(earlier).toEqual(frozen);
});
