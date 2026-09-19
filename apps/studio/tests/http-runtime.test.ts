import { expect, it } from 'vitest';
import { createHash } from 'node:crypto';
import { prefersMarkdown, publicPagePlan } from '../shared/public-site';
import { imageDigest, readImageBody, IMAGE_BYTES_LIMIT } from '../shared/images';
import { mediaByteRange, mediaResponsePlan, writeMediaChunks, MediaUploadError, MEDIA_CHUNK_BYTES } from '../shared/media';
import * as oracle from './oracle/http-policy';

it('matches original HTTP negotiation and range semantics across mixed headers', () => {
  let seed = 73519;
  const random = (length: number) => { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed % length; };
  const mime = ['text/html', 'text/markdown', '*/*', 'text/*', 'TEXT/MARKDOWN', 'text/html '];
  const languages = ['fr', 'ja-JP', 'en-GB', 'ja', 'en', '*', 'invalid_tag', 'en-US-x-test'];
  const quality = ['', ';q=0', ';q=1.', ';q=0.1', ';q=0.001', ';q=0.0001', ';q=1.001', '; q = 0.8', ';Q=0.4;q=1', ';q=NaN', ';x=y;q=1', ';q==1'];
  const paths = ['/', '/ja/', '/index.html?lang=en', '/?lang=ja', '/?room=', '/studio', '/unknown'];
  const bounds = ['', '0', '1', '4', '10', '999999', '9007199254740991', '9007199254740993', '-1', '2.3', '1-2,4-5'];
  for (let index = 0; index < 1200; index++) {
    const accept = Array.from({ length: random(5) }, () => mime[random(mime.length)] + quality[random(quality.length)]).join(', ');
    const language = Array.from({ length: random(5) }, () => languages[random(languages.length)] + quality[random(quality.length)]).join(', ');
    const url = new URL(paths[random(paths.length)], 'https://poietra.test');
    const headers = new Headers({ Accept: accept, 'Accept-Language': language });
    expect(prefersMarkdown(accept), accept).toBe(oracle.prefersMarkdown(accept));
    expect(publicPagePlan(url, headers), language).toEqual(oracle.publicPagePlan(url, headers));
    const range = `bytes=${bounds[random(bounds.length)]}-${bounds[random(bounds.length)]}`;
    const size = random(101), request = { range, ifRange: index % 3 ? null : '"old"', ifNoneMatch: index % 7 ? null : 'W/"digest"' };
    expect(mediaByteRange(range, size), range).toEqual(oracle.mediaByteRange(range, size));
    expect(mediaResponsePlan(request, { size, mime: 'audio/wav' }, 'digest')).toEqual(oracle.mediaResponsePlan(request, { size, mime: 'audio/wav' }, 'digest'));
  }
});

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
    await new Promise(resolve => setTimeout(resolve, 1));
    expect(pulled).toBe(count);
    expect(chunk).toEqual(expected);
    expect(part).toBe(written.length);
    written.push(chunk.slice());
  });
  expect(allocations.size).toBe(1);
  expect(Buffer.concat(written)).toEqual(Buffer.from(bytes));
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
