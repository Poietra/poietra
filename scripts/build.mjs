import { execFileSync } from 'node:child_process';
import { copyFileSync, mkdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';

const root = fileURLToPath(new URL('../', import.meta.url));
function moon(...args) {
  execFileSync(process.execPath, [join(root, 'scripts/moon.mjs'), ...args], { cwd: root, stdio: 'inherit' });
}
execFileSync('python3', ['scripts/generate-adapters.py'], { cwd: root, stdio: 'inherit' });
execFileSync(process.execPath, ['scripts/client-runtime.mjs'], { cwd: root, stdio: 'inherit' });
moon('fmt');
for (const target of ['js', 'wasm']) {
  moon('build', '--release', '--target', target, ...(target === 'wasm' ? ['moonbit/motion'] : []));
}
const wasm = join(root, 'apps/studio/public/wasm');
mkdirSync(wasm, { recursive: true });
copyFileSync(join(root, '_build/wasm/release/build/motion/motion.wasm'), join(wasm, 'poietra_core.wasm'));
execFileSync(process.execPath, ['scripts/generate-bindings.mjs'], { cwd: root, stdio: 'inherit' });
