// Retained typed render timelines while native resource preparation is suspended.
// Sequential CPU work only; no media decoder, rasterizer or encoder is started.
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';
import assert from 'node:assert/strict';
import { environment, stats } from '../apps/studio/scripts/benchmark-environment.mjs';

const { values } = parseArgs({ options: {
  output: { type: 'string', default: 'test-results/headless-heap.json' },
  sample: { type: 'string' },
  scenario: { type: 'string' },
} });
const scenarios = [[100, 2, 0], [500, 12, 0], [500, 60, 0], [500, 12, 10]];
if (values.sample !== undefined) {
  if (!global.gc) throw new Error('Use --expose-gc for a sample.');
  const [objects, compositions, textEvery] = scenarios[Number(values.sample)];
  const { defaultState } = await import('../apps/studio/shared/model.js');
  const { makeBlankScene } = await import('../apps/studio/shared/demo.js');
  const { renderProjectFile } = await import('../_build/js/release/build/headless_render/headless_render.js');
  function fixture() {
    const scene = makeBlankScene('scene', 'Retained timeline');
    scene.width = 320; scene.height = 180;
    scene.objects = {}; scene.compositions = {}; scene.compositionOrder = []; scene.transitions = {};
    for (let i = 0; i < objects; i++) scene.objects[`o${i}`] = { id: `o${i}`, name: `Object ${i}`, kind: textEvery && i % textEvery === 0 ? 'text' : 'circle', order: i, groupId: null, locked: false };
    for (let c = 0; c < compositions; c++) {
      const id = `c${c}`; scene.compositionOrder.push(id);
      scene.compositions[id] = { id, name: `Composition ${c}`, accent: '#123456', duration: 1000,
        states: Object.fromEntries(Object.keys(scene.objects).map((id, i) => [id, defaultState(scene.objects[id].kind, {
          x: i % 25 * 12 + c, y: Math.floor(i / 25) * 8, width: 5, height: 5,
          ...(scene.objects[id].kind === 'text' ? { text: `Label ${i}, Composition ${c}, 日本語` } : {}),
        })])) };
      if (c) scene.transitions[`t${c}`] = { id: `t${c}`, fromId: `c${c-1}`, toId: id, duration: 250, tracks: {} };
    }
    return JSON.stringify({ version: 1, name: 'Headless heap fixture', sceneOrder: [scene.id], scenes: { [scene.id]: scene } });
  }
  const text = fixture();
  const unexpected = () => { throw new Error('This workload must not invoke media or rasterization.'); };
  function begin(blocked) {
    const entered = Promise.withResolvers(), release = Promise.withResolvers();
    const host = {
      loadMathRuntime: unexpected,
      prepare(texts, images) {
        assert.equal(texts.length, textEvery ? Math.ceil(objects / textEvery) * compositions : 0);
        assert.equal(new Set(texts).size, texts.length); assert.deepEqual(images, []);
        entered.resolve(); return blocked ? release.promise : undefined;
      },
      // Deterministic mock metrics only; real fonts are covered by renderer tests.
      measureLine: (line, size) => ({ left: 0, right: line.length * size / 2, ascent: size * 0.8, descent: size * 0.2 }), fontStyles: () => '',
      svgBytes: svg => new TextEncoder().encode(svg),
      png: unexpected, rgba: unexpected, readAudio: unexpected, createEncoder: unexpected, progress() {},
    };
    return { entered: entered.promise, release: release.resolve, result: renderProjectFile(text, { format: 'svg' }, host) };
  }
  let outputSha256;
  async function finish(job) {
    job.release(); const result = await job.result;
    const svg = new TextDecoder().decode(result.bytes);
    assert.equal((svg.match(/data-object-id=/g) || []).length, objects);
    const hash = createHash('sha256').update(result.bytes).digest('hex');
    if (outputSha256) assert.equal(hash, outputSha256); else outputSha256 = hash;
  }
  for (let i = 0; i < 2; i++) await finish(begin(false));
  global.gc();
  const before = process.memoryUsage().heapUsed, held = [], preparationMs = [];
  for (let i = 0; i < 3; i++) {
    const start = performance.now(), job = begin(true);
    await job.entered; preparationMs.push(performance.now() - start); held.push(job);
  }
  global.gc();
  const retainedBytes = (process.memoryUsage().heapUsed - before) / held.length;
  for (const job of held) await finish(job);
  console.log(JSON.stringify({ objects, compositions, textEvery, inputBytes: Buffer.byteLength(text),
    inputSha256: createHash('sha256').update(text).digest('hex'), outputSha256,
    retainedBytes, preparationMs: stats(preparationMs), rawPreparationMs: preparationMs }));
} else {
  const report = { measuredAt: new Date().toISOString(), environment: environment(),
    harnessSha256: createHash('sha256').update(readFileSync(new URL(import.meta.url))).digest('hex'),
    headlessArtifactSha256: createHash('sha256').update(readFileSync(new URL('../_build/js/release/build/headless_render/headless_render.js', import.meta.url))).digest('hex'),
    method: 'Five fresh Node processes per case, sequential. Two completed warmup renders, then three render jobs prepared sequentially and held at the native resource-preparation port. Retained JS heap delta after forced GC divided by three, relative to the already-created input string. Includes typed timelines and suspended orchestration, excludes transient/peak memory, source string, file I/O, fonts/media, native/WASM memory and encoding. Preparation time includes public string parsing, timeline compilation and reaching the resource port, without forced GC inside each timed interval. After measuring, every job completes SVG rendering and verifies object count and identical bytes. Text scenarios use deterministic mock metrics with no font loading. No real native rendering backend is benchmarked.', results: [] };
  const selected = values.scenario === undefined ? scenarios.map((_, index) => index) : [Number(values.scenario)];
  if (selected.some(index => !Number.isInteger(index) || index < 0 || index >= scenarios.length)) throw new Error('Invalid --scenario');
  for (const scenario of selected) {
    const samples = [];
    for (let run = 0; run < 5; run++) {
      console.error(`Headless retained heap ${scenarios[scenario].join(' x ')}: ${run + 1}/5`);
      samples.push(JSON.parse(execFileSync(process.execPath, ['--expose-gc', fileURLToPath(import.meta.url), '--sample', String(scenario)], { encoding: 'utf8', timeout: 120000 })));
    }
    assert.equal(new Set(samples.map(s => s.inputSha256)).size, 1);
    assert.equal(new Set(samples.map(s => s.outputSha256)).size, 1);
    report.results.push({ objects: samples[0].objects, compositions: samples[0].compositions, textEvery: samples[0].textEvery,
      retainedBytes: stats(samples.map(s => s.retainedBytes)), preparationMs: stats(samples.map(s => s.preparationMs.median)), samples });
  }
  const output = resolve(values.output); mkdirSync(dirname(output), { recursive: true });
  writeFileSync(output, JSON.stringify(report, null, 2) + '\n');
  console.table(report.results.map(({ objects, compositions, retainedBytes, preparationMs }) => ({ objects, compositions, retainedMiB: retainedBytes.median / 2 ** 20, preparationMs: preparationMs.median })));
}
