import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, cpSync, mkdirSync, symlinkSync, readFileSync, writeFileSync, rmSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';

const root = fileURLToPath(new URL('../', import.meta.url));
test('a new typed MoonBit record becomes a callable JS API with matching public types', async () => {
  const directory = mkdtempSync(join(tmpdir(), 'poietra-extension-'));
  try {
    cpSync(join(root, 'moonbit'), join(directory, 'moonbit'), { recursive: true });
    for (const file of ['moon.mod', 'package.json']) cpSync(join(root, file), join(directory, file));
    for (const file of ['.mooncakes', '.tools', 'node_modules']) symlinkSync(join(root, file), join(directory, file));
    mkdirSync(join(directory, 'apps/studio/shared'), { recursive: true });
    const model = join(directory, 'moonbit/scene/model.mbt');
    writeFileSync(model, readFileSync(model, 'utf8') + `
///|
pub(all) struct ExtensionMetadata { label : String?; weights : Array[Double]; easing : Easing }
///|
pub(all) struct ExtensionRecord { id : String; metadata : ExtensionMetadata? }
`);
    execFileSync('python3', [join(root, 'scripts/generate-adapters.py'), '--root', directory]);
    const pkg = join(directory, 'moonbit/boundary/moon.pkg');
    writeFileSync(pkg, readFileSync(pkg, 'utf8').replace('targets: {', 'targets: { "extension_probe.mbt": ["js"],')
      .replace('"exports": [', '"exports": ["extension_roundtrip:extensionRoundtrip",'));
    writeFileSync(join(directory, 'moonbit/boundary/extension_probe.mbt'), `
///|
pub fn extension_roundtrip(value : @core.Any) -> @core.Any {
  encode_ExtensionRecord(decode_ExtensionRecord(value))
}
`);
    const local = join(root, '.tools/moon');
    const moon = process.env.POIETRA_MOON ?? (existsSync(join(local, 'bin/moon')) ? join(local, 'bin/moon') : 'moon');
    execFileSync(moon, ['build', '--release', '--target', 'js', 'moonbit/boundary'], {
      cwd: directory, env: { ...process.env, ...(moon === join(local, 'bin/moon') ? { MOON_HOME: local } : {}) }, stdio: 'pipe',
    });
    const api = await import(join(directory, '_build/js/release/build/boundary/boundary.js'));
    const fixture = { id: 'extension', metadata: { label: 'A new feature', weights: [0, .25, 1], easing: 'linear' } };
    assert.deepEqual(api.extensionRoundtrip(fixture), fixture);
    assert.deepEqual(api.extensionRoundtrip({ id: 'absent' }), { id: 'absent' });
    assert.deepEqual(api.extensionRoundtrip({ id: 'nullable', metadata: null }), { id: 'nullable' });
    writeFileSync(join(directory, 'consumer.ts'), `
import type { ExtensionRecord } from './apps/studio/shared/scene-types';
const example: ExtensionRecord = ${JSON.stringify(fixture)};
const optional: ExtensionRecord = { id: 'optional' };
// @ts-expect-error A generated feature retains its numeric element type.
const invalid: ExtensionRecord = { id: 'invalid', metadata: { weights: ['wrong'], easing: 'linear' } };
`);
    execFileSync('pnpm', ['exec', 'tsc', '--noEmit', '--strict', '--skipLibCheck', '--target', 'ES2023',
      '--ignoreConfig', '--module', 'ESNext', '--moduleResolution', 'Bundler', join(directory, 'consumer.ts')], { cwd: join(root, 'apps/studio'), stdio: 'pipe' });
  } finally { rmSync(directory, { recursive: true, force: true }); }
});
