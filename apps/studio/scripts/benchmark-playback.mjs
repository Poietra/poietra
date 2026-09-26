// Build first. Each sample runs alone in a fresh process with explicit GC.
import { execFileSync } from 'node:child_process';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';
import { environment, stats } from './benchmark-environment.mjs';

const { values } = parseArgs({ options: {
  output: { type: 'string', default: 'test-results/benchmarks/playback.json' },
  runs: { type: 'string', default: '5' },
  sample: { type: 'string' },
} });
const scenarios = [[100, 2, false], [500, 2, false], [500, 12, false], [500, 12, true]];
if (values.sample !== undefined) {
  if (!global.gc) throw new Error('The sample process needs --expose-gc');
  const [objects, compositions, parents] = scenarios[Number(values.sample)];
  const { makeDemoProject } = await import('../shared/demo.js');
  const { defaultTrack } = await import('../shared/model.js');
  const { compileScene } = await import('../src/engine/evaluate.js');
  const kernel = (await WebAssembly.instantiate(readFileSync(new URL('../public/wasm/poietra_core.wasm', import.meta.url)))).instance.exports;
  const scene = makeDemoProject().scenes['scene-1'];
  const object = scene.objects.circle;
  const state = scene.compositions['comp-1'].states.circle;
  const composition = scene.compositions['comp-1'];
  scene.objects = {};
  scene.compositions = {};
  scene.transitions = {};
  scene.compositionOrder = [];
  for (let index = 0; index < objects; index++) {
    const id = `object-${index}`;
    scene.objects[id] = { ...object, id, order: index,
      ...(parents && index % 10 ? { parentId: `object-${index - index % 10}` } : {}),
    };
  }
  for (let index = 0; index < compositions; index++) {
    const id = `composition-${index}`;
    scene.compositionOrder.push(id);
    scene.compositions[id] = { ...composition, id, states: Object.fromEntries(Object.keys(scene.objects).map((objectId, order) => [objectId,
      { ...state, x: order * 2 + index * 30, y: order % 10 * 10, path: { c1: { x: index, y: 10 }, c2: { x: 40, y: index } } },
    ])) };
    if (index) {
      const transitionId = `transition-${index}`;
      scene.transitions[transitionId] = { id: transitionId, fromId: `composition-${index - 1}`, toId: id, duration: 1000,
        tracks: Object.fromEntries(Object.keys(scene.objects).map(objectId => [objectId, defaultTrack(objectId, { duration: 1000 })])),
      };
    }
  }
  let checksum = 0;
  for (let index = 0; index < 3; index++) checksum += compileScene(scene, kernel).evaluate(1500).objects[0].state.x;
  const prepareMs = [];
  for (let index = 0; index < 7; index++) {
    global.gc();
    const start = performance.now();
    const program = compileScene(scene, kernel);
    prepareMs.push(performance.now() - start);
    checksum += program.evaluate(1500).objects[0].state.x;
  }
  // Keep the caller's input alive in both conditions; count only additional
  // retained JS heap. Eight handles reduce fixed allocation/GC noise.
  const programs = [];
  global.gc();
  const before = process.memoryUsage().heapUsed;
  for (let index = 0; index < 8; index++) programs.push(compileScene(scene, kernel));
  global.gc();
  const retainedBytes = (process.memoryUsage().heapUsed - before) / programs.length;
  for (const program of programs) checksum += program.evaluate(1500).objects[0].state.x;
  console.log(JSON.stringify({ objects, compositions, parents, prepareMs, retainedBytes, checksum }));
} else {
  const runs = Number(values.runs);
  if (!Number.isInteger(runs) || runs < 1 || runs > 9) throw new Error('--runs must be 1..9');
  const report = { measuredAt: new Date().toISOString(), environment: environment(),
    method: 'Sequential fresh Node processes; three compile warmups, seven timed compilations (GC outside timing), then eight retained programs with explicit GC. Heap delta excludes the caller input, WASM/native memory, and transient allocations. CPU setup only, not browser FPS.',
    results: [],
  };
  for (let scenario = 0; scenario < scenarios.length; scenario++) {
    const samples = [];
    for (let run = 0; run < runs; run++) {
      const [objects, compositions, parents] = scenarios[scenario];
      console.error(`playback ${objects} objects / ${compositions} compositions / parents=${parents}: process ${run + 1}/${runs}`);
      samples.push(JSON.parse(execFileSync(process.execPath, ['--expose-gc', fileURLToPath(import.meta.url), '--sample', String(scenario)], { encoding: 'utf8', timeout: 120000 })));
    }
    report.results.push({ objects: scenarios[scenario][0], compositions: scenarios[scenario][1], parents: scenarios[scenario][2],
      prepareMs: stats(samples.map(sample => stats(sample.prepareMs).median)),
      retainedBytes: stats(samples.map(sample => sample.retainedBytes)), samples,
    });
  }
  report.completedAt = new Date().toISOString();
  const output = resolve(values.output);
  mkdirSync(dirname(output), { recursive: true });
  writeFileSync(output, JSON.stringify(report, null, 2) + '\n');
  console.table(report.results.map(({ objects, compositions, parents, prepareMs, retainedBytes }) => ({ objects, compositions, parents, prepareMs: prepareMs.median, retainedBytes: retainedBytes.median })));
  console.error(`Saved ${output}`);
}
