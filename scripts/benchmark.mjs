// Measurements are sequential. Build first, then stop other tests/encoders.
import { execFileSync } from 'node:child_process';
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { parseArgs } from 'node:util';
import { environment, root, stats } from '../apps/studio/scripts/benchmark-environment.mjs';

const { values } = parseArgs({ options: { output: { type: 'string', default: 'test-results/benchmarks/cpu.json' }, runs: { type: 'string', default: '3' }, help: { type: 'boolean' } } });
if (values.help) {
  console.log('Usage: pnpm bench [--runs 1..9] [--output JSON_PATH]\nBuild first. Runs CPU benchmarks sequentially in fresh Node processes; no browser/server needed.');
  process.exit(0);
}
const count = Number(values.runs);
if (!Number.isInteger(count) || count < 1 || count > 9) throw new Error('--runs must be an integer from 1 to 9');
const output = resolve(values.output);
const result = { measuredAt: new Date().toISOString(), environment: environment(), method: 'Fresh processes, sequential scenarios; summary is median of process medians, speedup is ratio of those medians. Min/max span process medians, not individual operations.', runs: count, suites: {} };
for (const [name, script, fields] of [
  ['evaluation', 'benchmark-moonbit.ts', ['originalMsPerFrame', 'moonbitMsPerFrame', 'prepareMs']],
  ['snapshots', 'benchmark-snapshots.ts', ['originalMsPerEditAndRead', 'moonbitMsPerEditAndRead']],
  ['proposals', 'benchmark-proposals.ts', ['originalMs', 'moonbitMs']],
]) {
  const samples = [];
  for (let run = 0; run < count; run++) {
    console.error(`${name}: process ${run + 1}/${count}`);
    samples.push(JSON.parse(execFileSync(process.execPath, ['--import', 'tsx', `scripts/${script}`], { cwd: join(root, 'apps/studio'), encoding: 'utf8', timeout: 180000 })));
  }
  const summary = samples[0].results.map((row, index) => {
    const dimensions = Object.fromEntries(Object.entries(row).filter(([key]) => ![...fields, 'speedup', 'samples'].includes(key)));
    const metrics = Object.fromEntries(fields.map(field => [field, stats(samples.map(sample => sample.results[index][field]))]));
    return { ...dimensions, ...metrics, speedup: metrics[fields[0]].median / metrics[fields[1]].median };
  });
  result.suites[name] = { summary, samples };
  console.table(summary.map(row => Object.fromEntries(Object.entries(row).map(([key, value]) => [key, typeof value === 'object' ? value.median : value]))));
}
result.completedAt = new Date().toISOString();
result.loadAverageAfter = environment().loadAverage;
mkdirSync(dirname(output), { recursive: true });
writeFileSync(output, JSON.stringify(result, null, 2) + '\n');
console.error(`Saved ${output}`);
