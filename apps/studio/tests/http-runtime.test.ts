import { expect, it } from 'vitest';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { imageDigest, readImageBody, IMAGE_BYTES_LIMIT } from '../shared/images';
import { writeMediaChunks, MediaUploadError, MEDIA_CHUNK_BYTES } from '../shared/media';

it('holds one upload buffer, preserves bytes and backpressure, and closes the source on sink failure', async () => {
  const bytes = new Uint8Array(MEDIA_CHUNK_BYTES * 3 + 17);
  bytes.set(new TextEncoder().encode('RIFF0000WAVE'));
  bytes[MEDIA_CHUNK_BYTES + 51] = 123;
  let pulled = 0, closed = 0;
  async function* source() { try { for (let offset = 0; offset < bytes.length; offset += 997) { pulled++; yield bytes.subarray(offset, offset + 997); } } finally { closed++; } }
  const allocations = new Set<ArrayBufferLike>(), written: Uint8Array[] = [];
  await writeMediaChunks(source(), 'audio/wav', null, async (chunk, part) => {
    const count = pulled, expected = chunk.slice();
    allocations.add(chunk.buffer);
    await new Promise<void>(resolve => setImmediate(resolve));
    expect(pulled).toBe(count);
    // Compare bytes natively instead of recursively matching every array element.
    assert.deepEqual(chunk, expected);
    expect(part).toBe(written.length);
    written.push(chunk.slice());
  });
  expect(allocations.size).toBe(1);
  assert.deepEqual(Buffer.concat(written), Buffer.from(bytes));
  expect(closed).toBe(1);
  const diskFailure = new Error('disk unavailable');
  await expect(writeMediaChunks(source(), 'audio/wav', null, () => { throw diskFailure; })).rejects.toBe(diskFailure);
  expect(closed).toBe(2);
  const invalid = (async function* () { yield new Uint8Array(MEDIA_CHUNK_BYTES); })();
  await expect(writeMediaChunks(invalid, '', null, () => {})).rejects.toBeInstanceOf(MediaUploadError);
});

it('coalesces fragmented images, hashes exact bytes and releases rejected or failed readers', async () => {
  const bytes = new Uint8Array(1024);
  bytes.set([137, 80, 78, 71, 13, 10, 26, 10]);
  let position = 0;
  const body = new ReadableStream<Uint8Array>({ pull(controller) { if (position < bytes.length) controller.enqueue(bytes.subarray(position, ++position)); else controller.close(); } });
  const request = new Request('http://local', { method: 'POST', body, ...{ duplex: 'half' } });
  const result = await readImageBody(request);
  expect(result).toEqual(bytes);
  expect(body.locked).toBe(false);
  expect(await imageDigest(result)).toBe(createHash('sha256').update(bytes).digest('hex'));
  let canceled = 0;
  const oversized = new ReadableStream<Uint8Array>({ pull(controller) { controller.enqueue(new Uint8Array(IMAGE_BYTES_LIMIT + 1)); }, cancel() { canceled++; } });
  await expect(readImageBody(new Request('http://local', { method: 'POST', body: oversized, ...{ duplex: 'half' } }))).rejects.toThrow('1 MB');
  expect(canceled).toBe(1); expect(oversized.locked).toBe(false);
  const failure = new Error('connection lost');
  const broken = new ReadableStream({ pull(controller) { controller.error(failure); } });
  await expect(readImageBody(new Request('http://local', { method: 'POST', body: broken, ...{ duplex: 'half' } }))).rejects.toBe(failure);
  expect(broken.locked).toBe(false);
});
