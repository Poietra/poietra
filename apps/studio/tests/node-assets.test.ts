import { mkdtemp, mkdir, open, readdir, readFile, rm, stat } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { expect, it } from 'vitest';
import { createServer, request as httpRequest } from 'node:http';
import { saveRoomImage } from '../server/images';
import { handleMedia } from '../server/media';
import { MEDIA_FILE_LIMIT } from '../shared/media';
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

it('delivers an HTTP size error while a declared oversized body is still arriving', async () => {
  const root = await mkdtemp(join(tmpdir(), 'poietra-node-rejection-'));
  const previous = process.env.POIETRA_DATA_DIR;
  process.env.POIETRA_DATA_DIR = root;
  const server = createServer(async (request, response) => {
    if (!await handleMedia(request, response, request.url!)) { response.statusCode = 404; response.end(); }
  });
  try {
    await new Promise<void>(resolve => server.listen(0, '127.0.0.1', resolve));
    const address = server.address(); if (!address || typeof address === 'string') throw new Error('No address');
    const origin = `http://127.0.0.1:${address.port}`;
    let sent = 0;
    const body = new ReadableStream<Uint8Array>({ async pull(controller) {
      await new Promise(resolve => setTimeout(resolve, 2));
      if (sent === MEDIA_FILE_LIMIT + 1) { controller.close(); return; }
      const size = Math.min(512 * 1024, MEDIA_FILE_LIMIT + 1 - sent);
      sent += size; controller.enqueue(new Uint8Array(size));
    } });
    const result = await fetch(`${origin}/api/rooms/${crypto.randomUUID()}/media`, {
      method: 'POST', headers: { Origin: origin, 'Content-Type': 'audio/wav', 'Content-Length': String(MEDIA_FILE_LIMIT + 1) }, body, ...{ duplex: 'half' },
    });
    expect(result.status).toBe(413);
    expect(await result.json()).toEqual({ error: '音声・動画は 32 MB 以下にしてください。' });
    // A client that never finishes must still receive the rejection promptly.
    await new Promise<void>((resolve, reject) => {
      const pending = httpRequest(`${origin}/api/rooms/${crypto.randomUUID()}/media`, {
        method: 'POST', headers: { Origin: origin, 'Content-Length': String(MEDIA_FILE_LIMIT + 1) },
      }, response => {
        const chunks: Buffer[] = [];
        response.on('data', chunk => chunks.push(chunk));
        response.on('end', () => {
          clearTimeout(timeout); pending.destroy();
          try { expect(response.statusCode).toBe(413); expect(JSON.parse(Buffer.concat(chunks).toString()).error).toContain('32 MB'); resolve(); }
          catch (error) { reject(error); }
        });
      });
      const timeout = setTimeout(() => { pending.destroy(); reject(new Error('Rejected request retained its stalled body')); }, 4000);
      pending.on('error', error => { clearTimeout(timeout); reject(error); });
      pending.write(new Uint8Array(16));
    });
  } finally {
    await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
    if (previous === undefined) delete process.env.POIETRA_DATA_DIR; else process.env.POIETRA_DATA_DIR = previous;
    await rm(root, { recursive: true, force: true });
  }
});
