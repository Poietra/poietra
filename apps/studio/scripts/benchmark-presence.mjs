/** Frozen-artifact CPU benchmark; no network or browser FPS claim. */
import assert from 'node:assert/strict';
import { readFile, writeFile } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';
import { cpus, totalmem } from 'node:os';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { parseArgs } from 'node:util';
import { createHash } from 'node:crypto';
import * as decoding from 'lib0/decoding';

const { values: args } = parseArgs({ options: {
  module: { type: 'string' }, output: { type: 'string' }, 'source-revision': { type: 'string' },
} });
assert(args.module && args.output, '--module <frozen JS> --output <json> required');
const modulePath = resolve(args.module), { presenceMessages } = await import(pathToFileURL(modulePath));
const fixture = (count, unicode = false) => Array.from({ length: count }, (_, i) => ({
  clientId: 2 ** 32 + i, clock: 2 ** 32 + 73,
  state: { user: { name: unicode ? '共同制作者'.repeat(8) : `Peer ${i}`, color: '#abcdef' },
    editor: { sceneId: 'scene-1', compositionId: 'comp-1',
      selectedIds: unicode ? Array.from({ length: 12 }, (_, j) => `${j}${'図形'.repeat(39)}`) : [`load-${i}`],
      cursor: { x: i * 1.25, y: 0 - i * 0.25 } } },
}));
const workloads = [];
for (const [name, entries] of [['cursor-batch', fixture(64)], ['full-roster', fixture(500)], ['unicode-roster', fixture(500, true)]]) {
  const packets = presenceMessages(entries), decoded = [];
  for (const packet of packets) {
    assert(packet.byteLength < 16384);
    const outer = decoding.createDecoder(packet); assert.equal(decoding.readVarUint(outer), 1);
    const inner = decoding.createDecoder(decoding.readVarUint8Array(outer)), count = decoding.readVarUint(inner);
    assert(count <= 100);
    for (let i = 0; i < count; i++) decoded.push({ clientId: decoding.readVarUint(inner), clock: decoding.readVarUint(inner), state: JSON.parse(decoding.readVarString(inner)) });
    assert.equal(inner.pos, inner.arr.byteLength); assert.equal(outer.pos, outer.arr.byteLength);
  }
  assert.deepEqual(decoded, entries);
  for (let i = 0; i < 30; i++) presenceMessages(entries);
  const samples = [];
  for (let sample = 0; sample < 5; sample++) {
    const start = performance.now();
    for (let i = 0; i < 200; i++) presenceMessages(entries);
    samples.push((performance.now() - start) / 200);
  }
  workloads.push({ name, entries: entries.length, packets: packets.length, bytes: packets.reduce((n, p) => n + p.byteLength, 0), millisecondsPerBatch: samples });
}
const digest = bytes => createHash('sha256').update(bytes).digest('hex');
const result = {
  measuredAt: new Date().toISOString(), sourceRevision: args['source-revision'] ?? execFileSync('git', ['rev-parse', 'HEAD'], { encoding: 'utf8' }).trim(),
  harnessRevision: execFileSync('git', ['rev-parse', 'HEAD'], { encoding: 'utf8' }).trim(),
  moduleSha256: digest(await readFile(modulePath)), harnessSha256: digest(await readFile(new URL(import.meta.url))),
  node: process.version, compiler: (await readFile(new URL('../../../.moon-version', import.meta.url), 'utf8')).trim(),
  machine: { platform: process.platform, cpu: cpus()[0].model, logicalCpus: cpus().length, memoryBytes: totalmem(), affinity: (await readFile('/proc/self/status', 'utf8')).match(/Cpus_allowed_list:\s*(.*)/)?.[1] },
  method: { warmupBatches: 30, samples: 5, iterationsPerSample: 200, timing: 'synchronous encoding only; excludes fixture creation and independent decode validation; no network' }, workloads,
};
await writeFile(args.output, JSON.stringify(result, null, 2) + '\n'); console.log(JSON.stringify(result, null, 2));
