import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';
import { cpus, totalmem, platform, release } from 'node:os';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { renderProjectFile } from '../apps/render/index.mjs';
import { project, addObject, addImage, addAudio } from '../apps/render/tests/fixtures.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const workloads = ['hold', 'motion', 'motion-audio'];
function workload(name) {
  const p = project(), s = p.scenes.scene;
  s.width = 1280; s.height = 720;
  s.compositions.a.duration = 1000; s.compositions.b.duration = 1600;
  s.transitions.transition.duration = 800; s.transitions.transition.tracks.box.duration = 800;
  for (const c of Object.values(s.compositions)) {
    c.states.box.x *= 4; c.states.box.y *= 4; c.states.box.width *= 4; c.states.box.height *= 4;
    c.states.box.effect = 'glow';
  }
  s.transitions.transition.tracks.box.keyframes.middle.value *= 4;
  addObject(p, 'title', 'text', { x: 640, y: 100, text: '友人と、AI と。Poietra', fontSize: 48, fill: '#ffffff', strokeWidth: 0 });
  addObject(p, 'math', 'equation', { x: 640, y: 560, text: '\\int_0^1 x^2\\,dx=\\frac13', fontSize: 52, fill: '#ffffff', strokeWidth: 0 });
  addImage(p);
  for (const c of Object.values(s.compositions)) Object.assign(c.states.image, { x: 1140, y: 100, width: 64, height: 64 });
  if (name === 'hold') {
    s.compositions.a.duration = 3400; delete s.compositions.b;
    s.compositionOrder = ['a']; s.transitions = {};
  }
  if (name === 'motion-audio') addAudio(p);
  return JSON.stringify(p);
}
if (process.argv[2] === '--sample') {
  const input = workload(process.argv[3]), start = performance.now();
  const { bytes, ...result } = await renderProjectFile(input, { format: 'mp4', fps: 30 });
  console.log(JSON.stringify({ ...result, wallMs: performance.now() - start, outputBytes: bytes.length,
    inputBytes: Buffer.byteLength(input), inputSha256: createHash('sha256').update(input).digest('hex') }));
} else {
  const output = resolve(process.argv[2] ?? 'test-results/headless-benchmark.json');
  const generated = await readFile(resolve(root, '_build/js/release/build/headless_render/headless_render.js'));
  const sourcePaths = ['scripts/benchmark-headless.mjs', 'apps/render/index.mjs', 'apps/render/worker.mjs',
    'apps/render/runtime-host.mjs', 'apps/render/tests/fixtures.mjs', 'pnpm-lock.yaml'];
  const sourceHashes = Object.fromEntries(await Promise.all(sourcePaths.map(async path =>
    [path, createHash('sha256').update(await readFile(resolve(root, path))).digest('hex')])));
  const run = name => JSON.parse(execFileSync(process.execPath, [fileURLToPath(import.meta.url), '--sample', name], { cwd: root, encoding: 'utf8' }));
  const samples = {};
  for (const name of workloads) {
    run(name); // One untimed warmup; every retained sample starts a fresh process/thread.
    samples[name] = Array.from({ length: 3 }, () => run(name));
  }
  const report = {
    date: new Date().toISOString(), revision: execFileSync('git', ['rev-parse', 'HEAD'], { cwd: root, encoding: 'utf8' }).trim(),
    workingTree: execFileSync('git', ['status', '--short'], { cwd: root, encoding: 'utf8' }).trim(),
    generatedSha256: createHash('sha256').update(generated).digest('hex'),
    sourceHashes,
    moon: (await readFile(resolve(root, '.moon-version'), 'utf8')).trim(),
    runtime: process.version, os: `${platform()} ${release()}`, cpu: cpus()[0].model, logicalCpus: cpus().length, memoryBytes: totalmem(),
    affinity: (await readFile('/proc/self/status', 'utf8')).match(/^Cpus_allowed_list:\s*(.*)$/m)?.[1],
    dependencies: JSON.parse(await readFile(resolve(root, 'apps/render/package.json'), 'utf8')).dependencies,
    method: 'Sequential runs on frozen sources, no concurrent build/test/encode. One warmup and three fresh-process samples per workload. wallMs includes worker startup, module/WASM loading, fonts, MathJax, rendering, encoding, muxing and thread teardown; excludes file/network transfer and independent decoding. peakRssBytes is the whole process high-water RSS. Not Cloudflare Worker memory or a comparison against browser export.',
    workload: '1280x720, 30 fps, 3.4 seconds (102 frames); rectangle Glow, Japanese/Latin text, equation and embedded PNG. Motion uses a normalized intermediate X key; audio adds a trimmed stereo 44.1 kHz WAV at half gain plus a muted track.',
    samples,
  };
  await mkdir(dirname(output), { recursive: true }); await writeFile(output, JSON.stringify(report, null, 2) + '\n');
  console.log(output);
  for (const [name, values] of Object.entries(samples)) console.log(name, values.map(x => ({ wallMs: x.wallMs, rasterizedFrames: x.rasterizedFrames, bytes: x.outputBytes, rssMiB: x.peakRssBytes / 2 ** 20 })));
}
