import { readFile } from 'node:fs/promises';
import { beforeAll, expect, test } from 'vitest';
import * as jsKernel from '../../../_build/js/release/build/motion/motion.js';
import { makeDemoProject } from '../shared/demo';
import { compileScene, compositionFrame } from '../src/engine/evaluate';
import type { MotionKernel } from '../src/engine/kernel';

let kernel: MotionKernel;
beforeAll(async () => {
  const bytes = await readFile(new URL('../public/wasm/poietra_core.wasm', import.meta.url));
  kernel = (await WebAssembly.instantiate(bytes)).instance.exports as unknown as MotionKernel;
});

test('MoonBit JS and WASM agree at finite and non-finite motion boundaries', () => {
  for (const value of [-Infinity, -1, -0, 0, .00001, .125, .25, .49999, .5, .75, .99999, 1, 2, Infinity, NaN]) {
    for (const kind of [0, 1, 2, 3, 99]) expect(kernel.ease(value, kind)).toBe(jsKernel.ease(value, kind));
    expect(kernel.interpolate(-120, 300, value)).toBe(jsKernel.interpolate(-120, 300, value));
    expect(kernel.cubic_bezier(-100, 35, 110, 20, value)).toBe(jsKernel.cubic_bezier(-100, 35, 110, 20, value));
    for (const [x1, y1, x2, y2] of [[0, 0, 0, 1], [1, 0, 1, 1], [1, 0, 0, 1], [.25, .1, .25, 1], [NaN, 0, 1, 1]]) {
      expect(kernel.cubic_bezier_ease(value, x1, y1, x2, y2)).toBe(jsKernel.cubic_bezier_ease(value, x1, y1, x2, y2));
    }
  }
});

test('compiled playback owns a snapshot and replacement programs see edits', () => {
  const scene = makeDemoProject().scenes['scene-1'];
  const program = compileScene(scene, kernel);
  const before = structuredClone(program.evaluate(1300));
  scene.compositions['comp-1'].states.circle.x = 1000;
  scene.objects.circle.name = 'A changed name';
  scene.transitions['transition-1'].tracks.circle.duration = 200;
  expect(program.evaluate(1300)).toEqual(before);
  expect(compileScene(scene, kernel).evaluate(1300)).not.toEqual(before);
});

test('typed write order stays a native string in transition and still frames', () => {
  const scene = makeDemoProject().scenes['scene-1'];
  for (const order of ['together', 'sequential'] as const) {
    scene.transitions['transition-1'].tracks.circle.order = order;
    const program = compileScene(scene, kernel);
    const change = program.transition('transition-1', 400);
    expect(change.objects.find(item => item.object.id === 'circle')!.order).toBe(order);
    expect(program.composition('comp-1').objects.every(item => item.order === 'together')).toBe(true);
  }
});

test('typed playback owns nested values while preserving public object metadata', () => {
  const scene = makeDemoProject().scenes['scene-1'];
  const object = Object.assign(scene.objects.circle, { extension: { labels: ['original'], nullable: null } });
  const track = scene.transitions['transition-1'].tracks.circle;
  track.easing = { type: 'cubicBezier', x1: .1, y1: .2, x2: .8, y2: .9 };
  track.path = { c1: { x: 40, y: 30 }, c2: { x: 80, y: 50 } };
  // Non-object extension data has no role in either evaluation or the public frame.
  Object.defineProperty(scene.compositions['comp-1'], 'extension', {
    enumerable: true, get() { throw new Error('Unconsumed composition data'); },
  });
  const program = compileScene(scene, kernel);
  const before = structuredClone(program.evaluate(1300));
  const originalObject = program.composition('comp-1').objects.find(item => item.object.id === 'circle')!.object;
  expect(originalObject).toEqual(object);
  expect(originalObject).not.toBe(object);
  scene.compositions['comp-1'].states.circle.path.c1.x = 900;
  scene.compositionOrder.reverse();
  object.extension.labels.push('changed');
  track.path.c1.x = 900;
  track.easing.x1 = .9;
  expect(program.evaluate(1300)).toEqual(before);
  const evaluatedObject = program.evaluate(1300).objects.find(item => item.object.id === 'circle')!.object;
  expect(evaluatedObject).toBe(originalObject);
  expect(evaluatedObject).toHaveProperty('extension', { labels: ['original'], nullable: null });
});

test('compiled programs retain earlier frames across seeks and zero-duration cuts', () => {
  const scene = makeDemoProject().scenes['scene-1'];
  scene.compositions['comp-1'].duration = 0;
  scene.transitions['transition-1'].duration = 0;
  const program = compileScene(scene, kernel);
  const earlier = program.evaluate(-1);
  const frozen = structuredClone(earlier);
  for (const time of [0, 3000, 10, 0]) {
    expect(program.evaluate(time).objects.find(item => item.object.id === 'circle')!.state.x)
      .toBe(scene.compositions['comp-2'].states.circle.x);
  }
  expect(program.evaluate(-100)).toEqual(frozen);
  expect(earlier).toEqual(frozen);
});

test('editing a composition does not decode other compositions or prepare transitions', () => {
  const scene = makeDemoProject().scenes['scene-1'];
  const first = scene.compositions['comp-1'];
  const expected = compositionFrame(scene, first);
  Object.defineProperty(scene.compositions['comp-2'], 'states', { get() { throw new Error('Unrelated composition decoded'); } });
  Object.defineProperty(scene.transitions['transition-1'], 'tracks', { get() { throw new Error('Unrelated transition compiled'); } });
  expect(compositionFrame(scene, first)).toEqual(expected);
});

test('caller-owned frozen containers still observe mutable metadata and poses', () => {
  const scene = makeDemoProject().scenes['scene-1'];
  Object.freeze(scene.objects);
  Object.freeze(scene);
  const first = scene.compositions['comp-1'];
  Object.freeze(first.states);
  Object.freeze(first);
  compositionFrame(scene, first);
  const parent = Object.keys(scene.objects).find(id => id !== 'circle')!;
  scene.objects.circle.parentId = parent;
  scene.objects.circle.order = -100;
  first.states[parent].x = 1234;
  first.states.circle.path.c1.x = 987;
  const expected = structuredClone(scene);
  const actual = compositionFrame(scene, first);
  expect(actual).toEqual(compositionFrame(expected, expected.compositions['comp-1']));
  expect(actual.objects[0].object.id).toBe('circle');
});
