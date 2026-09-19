import { mkdtemp, mkdir, open, readdir, readFile, rm, stat } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { expect, it } from 'vitest';
import { saveRoomImage } from '../server/images';
import { IMAGE_BYTES_LIMIT, IMAGE_ROOM_BYTES_LIMIT } from '../shared/images';

it('serializes concurrent image publication, preserves dedup at quota, and publishes only private complete files', async () => {
  const root = await mkdtemp(join(tmpdir(), 'poietra-node-images-'));
  const previous = process.env.POIETRA_DATA_DIR;
  process.env.POIETRA_DATA_DIR = root;
  try {
    const room = crypto.randomUUID(), directory = join(root, 'images', room);
    await mkdir(directory, { recursive: true });
    const occupied = await open(join(directory, '0'.repeat(64)), 'wx', 0o600);
    await occupied.truncate(IMAGE_ROOM_BYTES_LIMIT - 32); await occupied.close();
    const left = new Uint8Array(32), right = new Uint8Array(32);
    for (const bytes of [left, right]) bytes.set([137, 80, 78, 71, 13, 10, 26, 10]);
    right[31] = 42;
    const results = await Promise.allSettled([saveRoomImage(room, left), saveRoomImage(room, right)]);
    expect(results.map(result => result.status).sort()).toEqual(['fulfilled', 'rejected']);
    const winner = results.findIndex(result => result.status === 'fulfilled');
    const result = results[winner];
    if (result.status !== 'fulfilled') throw new Error('Missing successful upload');
    const bytes = winner === 0 ? left : right, filename = join(directory, result.value.split('/').at(-1)!);
    expect(new Uint8Array(await readFile(filename))).toEqual(bytes);
    expect((await stat(filename)).mode & 0o777).toBe(0o600);
    expect(await saveRoomImage(room, bytes)).toBe(result.value);
    expect((await readdir(directory)).every(name => /^[a-f0-9]{64}$/.test(name))).toBe(true);
    await expect(saveRoomImage('../outside', left)).rejects.toThrow('Invalid room');
    await expect(saveRoomImage(room, new Uint8Array(IMAGE_BYTES_LIMIT + 1))).rejects.toThrow('1 MB');
  } finally {
    if (previous === undefined) delete process.env.POIETRA_DATA_DIR; else process.env.POIETRA_DATA_DIR = previous;
    await rm(root, { recursive: true, force: true });
  }
});
