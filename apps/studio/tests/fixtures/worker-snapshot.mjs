import { cp, mkdir, symlink } from 'node:fs/promises';
import { join, resolve } from 'node:path';

// Preserve package-relative MoonBit imports while freezing the generated code
// and Worker entrypoints for restart/persistence tests.
export async function snapshotWorkerSource(root) {
  const repository = join(root, 'source');
  const studio = join(repository, 'apps', 'studio');
  await mkdir(studio, { recursive: true });
  await Promise.all([
    ...['worker', 'shared', 'server', 'package.json'].map(path => cp(resolve(path), join(studio, path), { recursive: true })),
    cp(resolve('../../_build/js/release/build'), join(repository, '_build/js/release/build'), { recursive: true }),
    cp(resolve('../../package.json'), join(repository, 'package.json')),
    symlink(resolve('../../node_modules'), join(repository, 'node_modules'), 'dir'),
    symlink(resolve('node_modules'), join(studio, 'node_modules'), 'dir'),
  ]);
  return studio;
}
