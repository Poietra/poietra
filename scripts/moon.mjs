import { execFileSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';

const root = fileURLToPath(new URL('../', import.meta.url));
const local = join(root, '.tools/moon');
const moon = process.env.POIETRA_MOON ?? (existsSync(join(local, 'bin/moon')) ? join(local, 'bin/moon') : 'moon');
const env = moon === join(local, 'bin/moon') ? { ...process.env, MOON_HOME: local } : process.env;
execFileSync(moon, process.argv.slice(2), { cwd: root, env, stdio: 'inherit' });
