// Measure the actual pure MoonBit source in an isolated release artifact.
// Build is excluded from samples. Run without other tests/builds/encoders.
import { execFileSync } from 'node:child_process';
import { cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { createHash } from 'node:crypto';
import { pathToFileURL } from 'node:url';
import { parseArgs } from 'node:util';
import { environment, root, stats } from '../apps/studio/scripts/benchmark-environment.mjs';

const { values } = parseArgs({ options: { output: { type: 'string', default: 'test-results/benchmarks/sound-effects.json' }, samples: { type: 'string', default: '20' } } });
const samples = Number(values.samples), warmup = 5;
if (!Number.isInteger(samples) || samples < 3 || samples > 100) throw new Error('--samples must be 3..100');
const directory = mkdtempSync(join(tmpdir(), 'poietra-sound-bench-'));
try {
  const source = join(root, 'moonbit/sound_effects');
  const files = ['catalog.mbt', 'synthesis.mbt', 'wave.mbt', 'moon.pkg'];
  const hashes = Object.fromEntries(files.map(file => [file, createHash('sha256').update(readFileSync(join(source, file))).digest('hex')]));
  mkdirSync(join(directory, 'moonbit/probe'), { recursive: true });
  mkdirSync(join(directory, 'moonbit/sound_effects'), { recursive: true });
  for (const file of files) cpSync(join(source, file), join(directory, 'moonbit/sound_effects', file));
  writeFileSync(join(directory, 'moon.mod'), 'name = "poietra/sound_probe"\nsource = "moonbit"\npreferred_target = "js"\n');
  writeFileSync(join(directory, 'moonbit/probe/moon.pkg'), `import { "poietra/sound_probe/sound_effects" }
options(link: { "js": { "format": "esm", "exports": ["count:count", "id:id", "duration:duration", "render:render"] } })
`);
  writeFileSync(join(directory, 'moonbit/probe/probe.mbt'), `
pub fn count() -> Int { @sound_effects.presets().length() }
pub fn id(index : Int) -> String { @sound_effects.presets()[index].id }
pub fn duration(index : Int) -> Double { @sound_effects.presets()[index].duration }
pub fn render(index : Int, duration : Double, seed : UInt) -> Bytes {
  match @sound_effects.synthesize(@sound_effects.presets()[index].voice, duration, 0.0, seed) {
    Ok(sound) => sound.wave()
    Err(message) => abort(message)
  }
}
`);
  const local = join(root, '.tools/moon');
  const moon = process.env.POIETRA_MOON ?? (existsSync(join(local, 'bin/moon')) ? join(local, 'bin/moon') : 'moon');
  execFileSync(moon, ['build', '--target', 'js', '--release'], { cwd: directory, env: { ...process.env, ...(moon === join(local, 'bin/moon') ? { MOON_HOME: local } : {}) }, stdio: 'pipe' });
  const api = await import(pathToFileURL(join(directory, '_build/js/release/build/probe/probe.js')).href);
  const result = { measuredAt: new Date().toISOString(), environment: environment(), sourceHashes: hashes,
    method: { warmup, samples, scope: 'synthesis + waveform/cue measurement + PCM16 WAV encoding; one uncached take per operation', exclusions: 'isolated compilation, browser, Web Audio, upload, video encoding; no Earshot baseline or subjective quality score' }, results: [] };
  for (let index = 0; index < api.count(); index++) {
    for (const duration of [api.duration(index), 3000]) {
      for (let i = 0; i < warmup; i++) api.render(index, duration, i + 1);
      const times = []; let bytes = 0;
      for (let i = 0; i < samples; i++) {
        const start = performance.now();
        const wave = api.render(index, duration, i + 1);
        times.push(performance.now() - start); bytes = wave.length;
      }
      result.results.push({ id: api.id(index), durationMs: duration, bytes, ms: stats(times), samplesMs: times });
    }
  }
  result.completedAt = new Date().toISOString();
  result.loadAverageAfter = environment().loadAverage;
  const output = resolve(values.output); mkdirSync(dirname(output), { recursive: true });
  writeFileSync(output, JSON.stringify(result, null, 2) + '\n');
  console.table(result.results.map(row => ({ id: row.id, durationMs: row.durationMs, medianMs: row.ms.median, minMs: row.ms.min, maxMs: row.ms.max })));
  console.log(`Saved ${output}`);
} finally { rmSync(directory, { recursive: true, force: true }); }
