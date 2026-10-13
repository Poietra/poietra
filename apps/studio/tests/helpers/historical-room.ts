import { execFileSync } from 'node:child_process';
import { mkdtempSync, rmSync, symlinkSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

// Compile the actual last single-row Room from Git into an isolated directory;
// never check a copied historical implementation into the application or tests.
export async function historicalRoomClass() {
  const root = fileURLToPath(new URL('../../../../', import.meta.url));
  const directory = mkdtempSync(join(tmpdir(), 'poietra-rollback-room-'));
  const revision = '7bad3d585039f809a04b971beb8ff7092063dc40';
  try {
    const archive = execFileSync('git', ['archive', revision, 'moonbit', 'moon.mod', 'package.json', 'apps/studio/shared/http-host.mjs'], { cwd: root, maxBuffer: 32 * 1024 * 1024 });
    execFileSync('tar', ['-xf', '-'], { cwd: directory, input: archive });
    for (const path of ['.mooncakes', 'node_modules']) symlinkSync(join(root, path), join(directory, path));
    execFileSync(process.execPath, [join(root, 'scripts/moon.mjs'), '-C', directory, 'build', '--release', '--target', 'js', 'moonbit/worker_room'], { stdio: 'pipe' });
    return (await import(join(directory, '_build/js/release/build/worker_room/worker_room.js'))).projectRoomClass;
  } finally { rmSync(directory, { recursive: true, force: true }); }
}
