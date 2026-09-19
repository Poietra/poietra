import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { cpus, loadavg, platform, release, totalmem } from 'node:os';
import { fileURLToPath } from 'node:url';

export const root = fileURLToPath(new URL('../../../', import.meta.url));
export function environment() {
  const git = (...args) => execFileSync('git', args, { cwd: root, encoding: 'utf8' }).trim();
  let affinity = null;
  try { affinity = readFileSync('/proc/self/status', 'utf8').match(/^Cpus_allowed_list:\s*(.+)$/m)?.[1] ?? null; } catch {}
  const hash = path => createHash('sha256').update(readFileSync(new URL(path, import.meta.url))).digest('hex');
  const sources = git('ls-files', '--cached', '--others', '--exclude-standard', '-z', '--',
    'moonbit', 'apps/studio/src', 'apps/studio/shared', 'apps/studio/server', 'apps/studio/worker',
    'moon.mod', '.moon-version', 'pnpm-lock.yaml', 'scripts/build.mjs', 'scripts/generate-adapters.py',
    'scripts/bindings.json', 'scripts/generate-bindings.mjs').split('\0').filter(Boolean)
    .filter(path => !path.endsWith('.mbti') && existsSync(join(root, path))).sort();
  const sourceHash = createHash('sha256');
  for (const path of sources) sourceHash.update(path).update('\0').update(readFileSync(join(root, path))).update('\0');
  return {
    applicationRevision: git('rev-parse', 'HEAD'),
    trackedModifications: git('diff', 'HEAD', '--name-only').split('\n').filter(Boolean),
    applicationSourcesSha256: sourceHash.digest('hex'),
    node: process.version, platform: `${platform()}/${process.arch}`, kernel: release(),
    cpu: cpus()[0]?.model, logicalCpus: cpus().length, affinity,
    memoryBytes: totalmem(), loadAverage: loadavg(),
    moonVersion: readFileSync(new URL('../../../.moon-version', import.meta.url), 'utf8').trim(),
    wasmSha256: hash('../public/wasm/poietra_core.wasm'),
    browserEditorSha256: hash('../../../_build/js/release/build/browser_editor/browser_editor.js'),
    boundarySha256: hash('../../../_build/js/release/build/boundary/boundary.js'),
  };
}
export function stats(values) {
  if (!values.length || values.some(value => !Number.isFinite(value))) throw new Error('Expected finite measurement samples.');
  const ordered = [...values].sort((a, b) => a - b);
  return { n: values.length, median: ordered[Math.floor(ordered.length / 2)], min: ordered[0], max: ordered.at(-1) };
}
