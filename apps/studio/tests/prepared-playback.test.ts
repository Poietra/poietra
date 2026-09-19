import { readFile } from 'node:fs/promises';
import { beforeAll, expect, test } from 'vitest';
import * as jsKernel from '../../../_build/js/release/build/motion/motion.js';
import { makeDemoProject } from '../shared/demo';
import { compileScene } from '../src/engine/evaluate';
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
