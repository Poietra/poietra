import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, cpSync, writeFileSync, mkdirSync, rmSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { tmpdir } from 'node:os';
import { spawnSync } from 'node:child_process';

const root = fileURLToPath(new URL('../../../', import.meta.url));
test('media_pipeline compiles independently on JS/WASM and rejects incompatible consumers', () => {
  const directory = mkdtempSync(join(tmpdir(), 'poietra-media-contract-'));
  const local = join(root, '.tools/moon');
  const moon = process.env.POIETRA_MOON ?? (existsSync(join(local, 'bin/moon')) ? join(local, 'bin/moon') : 'moon');
  const check = target => spawnSync(moon, ['check', '--target', target, '--deny-warn'], {
    cwd: directory, env: { ...process.env, ...(moon === join(local, 'bin/moon') ? { MOON_HOME: local } : {}) }, encoding: 'utf8',
  });
  try {
    cpSync(join(root, 'moonbit/media_pipeline'), join(directory, 'src'), { recursive: true });
    writeFileSync(join(directory, 'moon.mod'), 'name = "tests/media"\nsource = "src"\npreferred_target = "js"\n');
    mkdirSync(join(directory, 'src/consumer'));
    writeFileSync(join(directory, 'src/consumer/moon.pkg'), 'import { "tests/media" @media }\n');
    const consumer = join(directory, 'src/consumer/consumer.mbt');
    writeFileSync(consumer, [
      '///|',
      'pub async fn encode(frame : @media.RgbaFrame, encoder : @media.Encoder) -> Bytes {',
      '  @media.with_encoder(fn() { encoder }, async fn(owned) {',
      '    (owned.add_video)(frame)',
      '    (owned.finish)()',
      '  })',
      '}',
    ].join('\n') + '\n');
    for (const target of ['js', 'wasm']) {
      const result = check(target); assert.equal(result.status, 0, result.stderr);
    }
    for (const invalid of [
      'pub async fn invalid(encoder : @media.Encoder, audio : @media.StereoPcm) -> Unit { (encoder.add_video)(audio) }',
      'pub fn invalid() -> @media.RgbaFrame { { width: 1, height: 1, pixels: b"" } }',
      'pub fn invalid() -> @media.Encoder { { add_video: fn(_) { 1 }, add_audio: fn(_) {}, finish: fn() { b"" }, dispose: fn() {} } }',
    ]) {
      writeFileSync(consumer, '///|\n' + invalid + '\n');
      const result = check('js');
      assert.notEqual(result.status, 0, 'invalid media contract unexpectedly compiled');
      assert.match(result.stderr, /Mismatch|mismatch|read.only|construct|private/i);
    }
  } finally { rmSync(directory, { recursive: true, force: true }); }
});
