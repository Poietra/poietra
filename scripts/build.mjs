import { execFileSync } from 'node:child_process';
import { existsSync, copyFileSync, mkdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';

const root = fileURLToPath(new URL('../', import.meta.url));
const local = join(root, '.tools/moon');
const moon = process.env.POIETRA_MOON ?? (existsSync(join(local, 'bin/moon')) ? join(local, 'bin/moon') : 'moon');
const env = moon === join(local, 'bin/moon') ? { ...process.env, MOON_HOME: local } : process.env;
execFileSync('python3', ['scripts/generate-adapters.py'], { cwd: root, stdio: 'inherit' });
execFileSync(process.execPath, ['scripts/client-runtime.mjs'], { cwd: root, stdio: 'inherit' });
execFileSync(moon, ['fmt'], { cwd: root, env, stdio: 'inherit' });
for (const target of ['js', 'wasm']) {
  execFileSync(moon, ['build', '--release', '--target', target, ...(target === 'wasm' ? ['moonbit/motion'] : [])], { cwd: root, env, stdio: 'inherit' });
}
const wasm = join(root, 'apps/studio/public/wasm');
mkdirSync(wasm, { recursive: true });
copyFileSync(join(root, '_build/wasm/release/build/motion/motion.wasm'), join(wasm, 'poietra_core.wasm'));
execFileSync(process.execPath, ['scripts/generate-bindings.mjs'], { cwd: root, stdio: 'inherit' });
