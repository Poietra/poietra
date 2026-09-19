import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import { prepareMedia, uploadMedia } from '../src/editor/media';
import { normalizeImage } from '../src/editor/images';

const runtime = vi.hoisted(() => ({ Input: vi.fn(), BlobSource: vi.fn(), CanvasSink: vi.fn(), AudioBufferSink: vi.fn(), ALL_FORMATS: [] }));
vi.mock('../src/platform/media-host.mjs', () => ({ mediaRuntime: () => runtime, audioRuntime: () => runtime }));
const file = () => new File(['RIFF0000WAVEdata'], 'voice.wav', { type: 'audio/x-wav' });
const deferred = <T>() => {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>(yes => { resolve = yes; });
  return { promise, resolve };
};
let input: { dispose: ReturnType<typeof vi.fn>; getPrimaryVideoTrack: ReturnType<typeof vi.fn>; getPrimaryAudioTrack: ReturnType<typeof vi.fn>; computeDuration: ReturnType<typeof vi.fn> };
let iterator: { next: ReturnType<typeof vi.fn>; return: ReturnType<typeof vi.fn> };
beforeEach(() => {
  vi.clearAllMocks();
  input = { dispose: vi.fn(), getPrimaryVideoTrack: vi.fn().mockResolvedValue(null), getPrimaryAudioTrack: vi.fn().mockResolvedValue({ canDecode: vi.fn().mockResolvedValue(true) }), computeDuration: vi.fn().mockResolvedValue(2) };
  iterator = { next: vi.fn().mockResolvedValue({ done: true }), return: vi.fn().mockResolvedValue({ done: true }) };
  runtime.Input.mockImplementation(function () { return input; });
  runtime.BlobSource.mockImplementation(function (blob) { return { blob }; });
  runtime.AudioBufferSink.mockImplementation(function () { return { buffersAtTimestamps: () => iterator }; });
});
afterEach(() => { vi.unstubAllGlobals(); vi.restoreAllMocks(); });

it('inspects the container and reads Float32 channels directly for a bounded waveform', async () => {
  const left = new Float32Array([.01234, -.76543]), right = new Float32Array([1.2]);
  iterator.next.mockResolvedValueOnce({ done: false, value: { buffer: { numberOfChannels: 2, getChannelData: (channel: number) => channel ? right : left } } });
  const progress = vi.fn(), prepared = await prepareMedia(file(), new AbortController().signal, progress);
  expect(prepared).toMatchObject({ kind: 'audio', asset: { mime: 'audio/wav', duration: 2000, hasAudio: true, waveform: [1] } });
  expect(prepared.blob.type).toBe('audio/wav');
  expect(await prepared.blob.text()).toBe(await file().text());
  expect(progress.mock.calls.map(([value]) => value)).toEqual([{ phase: 'reading', progress: 0 }, { phase: 'waveform', progress: 0 }, { phase: 'waveform', progress: 1 / 128 }]);
  expect(input.dispose).toHaveBeenCalledOnce(); expect(iterator.return).not.toHaveBeenCalled();
});

it('cancellation during track discovery disposes the input once and removes the abort listener', async () => {
  const wait = deferred<null>(), controller = new AbortController();
  input.getPrimaryVideoTrack.mockReturnValue(wait.promise);
  const remove = vi.spyOn(controller.signal, 'removeEventListener');
  const task = prepareMedia(file(), controller.signal), rejected = expect(task).rejects.toMatchObject({ name: 'AbortError' });
  await vi.waitFor(() => expect(input.getPrimaryVideoTrack).toHaveBeenCalledOnce());
  controller.abort(); wait.resolve(null); await rejected;
  expect(input.dispose).toHaveBeenCalledOnce();
  expect(remove).toHaveBeenCalledWith('abort', expect.any(Function));
});

it('a failed waveform closes the iterator and releases the input without replacing the error', async () => {
  const failure = new Error('decode failed'); iterator.next.mockRejectedValueOnce(failure);
  iterator.return.mockRejectedValueOnce(new Error('cleanup failed'));
  await expect(prepareMedia(file(), new AbortController().signal)).rejects.toBe(failure);
  expect(iterator.return).toHaveBeenCalledOnce(); expect(input.dispose).toHaveBeenCalledOnce();
});

it('synchronous runtime failures release the acquired input', async () => {
  const failure = new Error('probe failed'); input.getPrimaryVideoTrack.mockImplementationOnce(() => { throw failure; });
  await expect(prepareMedia(file(), new AbortController().signal)).rejects.toBe(failure);
  expect(input.dispose).toHaveBeenCalledOnce();
});

it('preflight cancellation from the progress callback starts no upload', async () => {
  const controller = new AbortController(), xhr = vi.fn(); vi.stubGlobal('XMLHttpRequest', xhr);
  await expect(uploadMedia('a'.repeat(32), file(), controller.signal, () => controller.abort())).rejects.toMatchObject({ name: 'AbortError' });
  expect(xhr).not.toHaveBeenCalled();
});

it('upload completion validates its path and releases all request callbacks', async () => {
  const controller = new AbortController(), source = `/api/rooms/${'a'.repeat(32)}/media/${'b'.repeat(64)}`;
  const xhr = { open: vi.fn(), setRequestHeader: vi.fn(), send: vi.fn(), abort: vi.fn(), upload: { onprogress: null as null | ((event: unknown) => void) }, onload: null as null | (() => void), onerror: null, ontimeout: null, onabort: null, status: 200, responseText: JSON.stringify({ src: source }) };
  vi.stubGlobal('XMLHttpRequest', function () { return xhr; });
  const remove = vi.spyOn(controller.signal, 'removeEventListener'), progress = vi.fn();
  const task = uploadMedia('a'.repeat(32), file(), controller.signal, progress);
  await vi.waitFor(() => expect(xhr.send).toHaveBeenCalledOnce());
  xhr.upload.onprogress?.({ loaded: 8, total: 8, lengthComputable: true });
  xhr.onload?.(); expect(await task).toBe(source);
  expect(progress).toHaveBeenLastCalledWith({ phase: 'saving', progress: 1 });
  expect([xhr.onload, xhr.onerror, xhr.ontimeout, xhr.onabort, xhr.upload.onprogress]).toEqual([null, null, null, null, null]);
  expect(remove).toHaveBeenCalledWith('abort', expect.any(Function));
});

it('image conversion errors release both the canvas and object URL', async () => {
  const failure = new Error('encode failed'), image = { src: '', naturalWidth: 10, naturalHeight: 10, decode: vi.fn().mockResolvedValue(undefined) };
  const canvas = { width: 0, height: 0, getContext: () => ({ drawImage() {} }), toBlob() { throw failure; } };
  vi.stubGlobal('Image', function () { return image; });
  vi.stubGlobal('document', { createElement: () => canvas });
  vi.spyOn(URL, 'createObjectURL').mockReturnValue('blob:test');
  const revoke = vi.spyOn(URL, 'revokeObjectURL').mockImplementation(() => {});
  await expect(normalizeImage(new File(['png'], 'image.png', { type: 'image/png' }))).rejects.toBe(failure);
  expect(canvas).toMatchObject({ width: 0, height: 0 }); expect(image.src).toBe(''); expect(revoke).toHaveBeenCalledWith('blob:test');
});
