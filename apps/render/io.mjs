import { open, mkdtemp, writeFile, link, rm } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';

export async function readProjectFile(path) {
  const file = await open(path, 'r');
  try {
    const stat = await file.stat();
    if (!stat.isFile() || stat.size > 32 * 1024 * 1024) throw new Error('Input must be a regular file of at most 32 MiB.');
    const chunks = []; let size = 0;
    for await (const chunk of file.createReadStream({ autoClose: false })) {
      size += chunk.length;
      if (size > 32 * 1024 * 1024) throw new Error('Input grew beyond 32 MiB.');
      chunks.push(chunk);
    }
    return new TextDecoder('utf-8', { fatal: true }).decode(Buffer.concat(chunks, size));
  } finally { await file.close(); }
}

// Publish a complete file atomically, without replacing an existing destination.
export async function writeResultFile(path, bytes, signal) {
  signal?.throwIfAborted();
  const target = resolve(path), temporary = await mkdtemp(join(dirname(target), '.poietra-render-'));
  try {
    const staged = join(temporary, 'result');
    await writeFile(staged, bytes, { signal });
    signal?.throwIfAborted();
    await link(staged, target);
  } finally { await rm(temporary, { recursive: true, force: true }); }
}
