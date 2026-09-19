import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { cpus, loadavg, platform, release, totalmem } from 'node:os';
import { fileURLToPath } from 'node:url';

export const root = fileURLToPath(new URL('../../../', import.meta.url));
export function environment() {
  const git = (...args) => execFileSync('git', args, { cwd: root, encoding: 'utf8' }).trim();
  let affinity = null;
  try { affinity = readFileSync('/proc/self/status', 'utf8').match(/^Cpus_allowed_list:\s*(.+)$/m)?.[1] ?? null; } catch {}
  const hash = path => createHash('sha256').update(readFileSync(new URL(path, import.meta.url))).digest('hex');
  return {
    applicationRevision: git('rev-parse', 'HEAD'),
    trackedModifications: git('diff', '--name-only').split('\n').filter(Boolean),
    node: process.version, platform: `${platform()}/${process.arch}`, kernel: release(),
    cpu: cpus()[0]?.model, logicalCpus: cpus().length, affinity,
    memoryBytes: totalmem(), loadAverage: loadavg(),
    moonVersion: readFileSync(new URL('../../../.moon-version', import.meta.url), 'utf8').trim(),
    wasmSha256: hash('../public/wasm/poietra_core.wasm'),
    rustOracleSha256: hash('../tests/oracle/rust-motion.wasm'),
  };
}
export function stats(values) {
  if (!values.length || values.some(value => !Number.isFinite(value))) throw new Error('Expected finite measurement samples.');
  const ordered = [...values].sort((a, b) => a - b);
  return { n: values.length, median: ordered[Math.floor(ordered.length / 2)], min: ordered[0], max: ordered.at(-1) };
}
