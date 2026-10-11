import test from 'node:test';
import assert from 'node:assert/strict';
import { PNG } from 'pngjs';
import { renderProjectFile, inspectProjectFile } from '../index.mjs';
import { spatialMathProject } from './fixtures.mjs';
import { decodeVideo } from './decode.mjs';

const pixel = (png, x, y) => [...png.data.subarray((y * png.width + x) * 4, (y * png.width + x) * 4 + 4)];
const render = (p, options) => renderProjectFile(JSON.stringify(p), options);

test('network definitions derive moving nodes, loops and parallel edges in PNG, SVG and independently decoded MP4', async () => {
  const p = spatialMathProject('network');
  assert.deepEqual(inspectProjectFile(JSON.stringify(p)).issues, []);
  const first = PNG.sync.read(Buffer.from((await render(p, { timeMs: 0 })).bytes));
  const middle = PNG.sync.read(Buffer.from((await render(p, { timeMs: 400 })).bytes));
  assert.deepEqual(pixel(first, 132, 106), [255, 255, 255, 255]);
  assert.deepEqual(pixel(middle, 162, 76), [255, 255, 255, 255]);
  assert.deepEqual(pixel(middle, 132, 106), [0, 0, 0, 255]);
  const video = await decodeVideo((await render(p, { format: 'mp4', fps: 30 })).bytes);
  assert.ok(video.frames[0].pixels[106 * 320 + 132] > 220);
  assert.ok(video.frames[12].pixels[76 * 320 + 162] > 220);
  assert.ok(video.frames[12].pixels[106 * 320 + 132] < 30);
  for (const c of Object.values(p.scenes.scene.compositions)) {
    const d = c.states.diagram.network;
    d.edges.loop = { ...d.edges.ab, from: 'a', to: 'a', directed: true, label: '<loop>', weight: null };
    d.edges.parallel = { ...d.edges.ab, bend: 1 };
    for (const n of Object.values(d.nodes)) n.label = '';
    d.nodes.a.label = '始点';
  }
  const svg = new TextDecoder().decode((await render(p, { format: 'svg' })).bytes);
  assert.match(svg, /data-geometry-element="edges\/loop" d="[^"]*C/);
  assert.match(svg, /data-geometry-element="edges\/parallel"/);
  assert.match(svg, /&lt;loop&gt;/); assert.doesNotMatch(svg, /NaN|Infinity/);
  const labelled = PNG.sync.read(Buffer.from((await render(p)).bytes));
  let count = 0;
  for (let y = 82; y < 94; y++) for (let x = 144; x < 171; x++) if (pixel(labelled, x, y)[0] > 50) count++;
  assert.ok(count > 20, 'Japanese network labels load bundled glyph fonts');
});

test('heightfield coefficients animate filled depth-sorted surfaces consistently in SVG, PNG and independently decoded MP4', async () => {
  const p = spatialMathProject('surface');
  assert.deepEqual(inspectProjectFile(JSON.stringify(p)).issues, []);
  const first = PNG.sync.read(Buffer.from((await render(p, { timeMs: 0 })).bytes));
  const middle = PNG.sync.read(Buffer.from((await render(p, { timeMs: 400 })).bytes));
  assert.ok(pixel(first, 147, 107)[0] > 100);
  assert.deepEqual(pixel(first, 147, 65), [0, 0, 0, 255]);
  assert.ok(pixel(middle, 147, 65)[0] > 100);
  assert.deepEqual(pixel(middle, 147, 107), [0, 0, 0, 255]);
  const video = await decodeVideo((await render(p, { format: 'mp4', fps: 30 })).bytes);
  assert.ok(video.frames[0].pixels[107 * 320 + 147] > 100);
  assert.ok(video.frames[12].pixels[65 * 320 + 147] > 100);
  assert.ok(video.frames[12].pixels[107 * 320 + 147] < 30);
  const svg = new TextDecoder().decode((await render(p, { format: 'svg', timeMs: 400 })).bytes);
  assert.match(svg, /data-geometry-element="faces\/[0-9]+"/);
  assert.match(svg, /fill="rgb\(/); assert.doesNotMatch(svg, /NaN|Infinity/);
  p.scenes.scene.compositions.a.states.diagram.visible = false;
  p.scenes.scene.transitions.transition.tracks.diagram.type = 'write';
  const empty = new TextDecoder().decode((await render(p, { format: 'svg', timeMs: 200 })).bytes);
  assert.doesNotMatch(empty, /data-geometry-element/);
  const partial = new TextDecoder().decode((await render(p, { format: 'svg', timeMs: 400 })).bytes);
  assert.match(partial, /fill-opacity="0.5"/);
});

test('parametric sphere and torus render, while undefined surface cells leave holes and documents keep formulas', async () => {
  const p = spatialMathProject('surface');
  for (const c of Object.values(p.scenes.scene.compositions)) Object.assign(c.states.diagram.surface, {
    kind: 'parametric', xExpression: 'a*cos(u)*sin(v)', yExpression: 'a*sin(u)*sin(v)', zExpression: 'a*cos(v)',
    uMin: 0, uMax: 2 * Math.PI, vMin: 0, vMax: Math.PI, a: 2, yaw: 35, pitch: 35, steps: 20,
  });
  const sphere = PNG.sync.read(Buffer.from((await render(p)).bytes));
  assert.ok(pixel(sphere, 161, 91)[0] > 50);
  for (const c of Object.values(p.scenes.scene.compositions)) Object.assign(c.states.diagram.surface, {
    xExpression: '(a+b*cos(v))*cos(u)', yExpression: '(a+b*cos(v))*sin(u)', zExpression: 'b*sin(v)',
    vMax: 2 * Math.PI, b: .7, pitch: 89,
  });
  const torus = PNG.sync.read(Buffer.from((await render(p)).bytes));
  assert.deepEqual(pixel(torus, 160, 90), [0, 0, 0, 255]);
  assert.ok(pixel(torus, 190, 90)[0] > 50);
  for (const c of Object.values(p.scenes.scene.compositions)) Object.assign(c.states.diagram.surface, {
    kind: 'heightfield', zExpression: '1/x', uMin: -1, uMax: 1, vMin: -1, vMax: 1, yaw: 0, pitch: 45, steps: 5,
  });
  const pole = PNG.sync.read(Buffer.from((await render(p)).bytes));
  assert.deepEqual(pixel(pole, 160, 90), [0, 0, 0, 255]);
  assert.doesNotMatch(JSON.stringify(p), /"(?:triangles|curves|world)":/);
});
