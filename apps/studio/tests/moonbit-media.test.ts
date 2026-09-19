import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const runtime = vi.hoisted(() => ({ Input: vi.fn(), BlobSource: vi.fn(), CanvasSink: vi.fn(), ALL_FORMATS: [] }));
vi.mock('../src/platform/media-host.mjs', () => ({ mediaRuntime: () => runtime }));

const imageSource = `/api/rooms/${'a'.repeat(16)}/images/${'b'.repeat(64)}`;
const mediaSource = `/api/rooms/${'a'.repeat(16)}/media/${'b'.repeat(64)}`;
function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>(yes => { resolve = yes; });
  return { promise, resolve };
}
const videoFrame = (time = 500) => ({ objects: [{ object: { id: 'video', kind: 'video', name: 'Clip',
  media: { src: mediaSource, duration: 2000 } }, state: { visible: true, opacity: 1 }, writeProgress: 1, videoTimeMs: time }] });
const imageScene = () => ({ objects: { image: { id: 'image', kind: 'image', name: 'Photo', image: { src: imageSource, width: 32, height: 32 } } },
  compositions: { first: { states: { image: { visible: true } } } } });

describe('MoonBit media streams and decoder lifetimes', () => {
  let moon: typeof import('../../../_build/js/release/build/browser_media/browser_media.js');
  let fetcher: ReturnType<typeof vi.fn>;
  let inputs: Array<{ dispose: ReturnType<typeof vi.fn>; getPrimaryVideoTrack: ReturnType<typeof vi.fn> }>;
  let decoded: ReturnType<typeof vi.fn>;
  let track: { canDecode: ReturnType<typeof vi.fn> };
  let canvases: Array<{ width: number; height: number }>;

  beforeEach(async () => {
    vi.resetModules(); vi.clearAllMocks(); inputs = []; canvases = [];
    track = { canDecode: vi.fn().mockResolvedValue(true) };
    decoded = vi.fn().mockResolvedValue({ canvas: { width: 128, height: 72 } });
    runtime.Input.mockImplementation(function () {
      const input = { dispose: vi.fn(), getPrimaryVideoTrack: vi.fn().mockResolvedValue(track) };
      inputs.push(input); return input;
    });
    runtime.BlobSource.mockImplementation(function (blob: Blob) { return { blob }; });
    runtime.CanvasSink.mockImplementation(function () { return { getCanvas: decoded }; });
    fetcher = vi.fn(() => Promise.resolve(new Response(new Uint8Array([1, 2, 3]), { headers: { 'Content-Type': 'image/png; charset=utf-8' } })));
    vi.stubGlobal('fetch', fetcher);
    vi.stubGlobal('document', { createElement: () => {
      const canvas = { width: 300, height: 150, getContext: () => ({ drawImage: vi.fn() }), toDataURL: () => 'data:image/png;base64,AQ==' };
      canvases.push(canvas); return canvas;
    } });
    vi.stubGlobal('FileReader', class {
      onload: (() => void) | null = null; onerror: (() => void) | null = null; result = '';
      readAsDataURL(_blob: Blob) { this.result = 'data:image/png;base64,AQ=='; queueMicrotask(() => this.onload?.()); }
    });
    moon = await import('../../../_build/js/release/build/browser_media/browser_media.js');
  });
  afterEach(() => { vi.unstubAllGlobals(); vi.restoreAllMocks(); });

  it('deduplicates image preparation and retries synchronous failures without retaining a rejected request', async () => {
    fetcher.mockImplementationOnce(() => { throw new Error('offline'); });
    await expect(moon.prepareImages(imageScene())).rejects.toThrow('offline');
    await Promise.all([moon.prepareImages(imageScene()), moon.prepareImages(imageScene())]);
    expect(fetcher).toHaveBeenCalledTimes(2);
    expect(moon.preparedImage(imageSource)).toBe('data:image/png;base64,AQ==');
  });

  it('rejects unsupported references and invalid dimensions before fetching', async () => {
    await expect(moon.imageBlob('https://example.org/image.png', undefined)).rejects.toThrow('参照');
    await expect(moon.openMedia('https://example.org/video.mp4', new AbortController().signal)).rejects.toThrow('参照');
    const scene = imageScene(); scene.objects.image.image.width = 2049;
    await expect(moon.prepareImages(scene)).rejects.toThrow('画像がありません');
    expect(fetcher).not.toHaveBeenCalled();
  });

  for (const failure of ['oversize', 'read', 'aborted'] as const) it(`cancels the reader and releases its lock after ${failure}`, async () => {
    const controller = new AbortController();
    const failureValue = new Error('reader failed');
    const reader = { read: vi.fn(async () => {
      if (failure === 'read') throw failureValue;
      if (failure === 'aborted') { controller.abort(); return { done: true }; }
      return { done: false, value: new Uint8Array(1024 * 1024 + 1) };
    }), cancel: vi.fn().mockResolvedValue(undefined), releaseLock: vi.fn() };
    fetcher.mockResolvedValueOnce({ ok: true, body: { getReader: () => reader }, headers: new Headers() } as never);
    const task = moon.imageBlob(imageSource, controller.signal);
    if (failure === 'aborted') await expect(task).rejects.toMatchObject({ name: 'AbortError' });
    else if (failure === 'read') await expect(task).rejects.toBe(failureValue);
    else await expect(task).rejects.toThrow('大きすぎ');
    expect(reader.cancel).toHaveBeenCalledOnce();
    expect(reader.releaseLock).toHaveBeenCalledOnce();
  });

  it('reuses the latest decoded frame and releases inactive inputs and temporary canvases', async () => {
    const videos = moon.createVideoFrames();
    const first = videoFrame();
    await videos.prepare(first);
    const next = videoFrame();
    await videos.prepare(next);
    expect(decoded).toHaveBeenCalledExactlyOnceWith(.5);
    expect(next.objects[0]).toHaveProperty('videoFrame', 'data:image/png;base64,AQ==');
    expect(canvases.every(canvas => canvas.width === 0 && canvas.height === 0)).toBe(true);
    await videos.prepare({ objects: [] });
    expect(inputs[0].dispose).toHaveBeenCalledOnce();
    videos.dispose(); videos.dispose();
    expect(inputs[0].dispose).toHaveBeenCalledOnce();
  });

  it('serializes overlapping seeks against a shared decoder without losing either result', async () => {
    const wait = deferred<unknown>();
    decoded.mockImplementationOnce(() => wait.promise);
    const videos = moon.createVideoFrames();
    const first = videoFrame(100), second = videoFrame(3000);
    const a = videos.prepare(first), b = videos.prepare(second);
    await vi.waitFor(() => expect(decoded).toHaveBeenCalledTimes(1));
    expect(second.objects[0]).not.toHaveProperty('videoFrame');
    wait.resolve({ canvas: { width: 128, height: 72 } });
    await Promise.all([a, b]);
    expect(decoded.mock.calls.map(args => args[0])).toEqual([.1, 1.999999]);
    expect(first.objects[0]).toHaveProperty('videoFrame');
    expect(second.objects[0]).toHaveProperty('videoFrame');
    expect(inputs).toHaveLength(1);
    videos.dispose();
  });

  it('disposes an input immediately during track discovery and cancels queued work', async () => {
    const pending = deferred<unknown>();
    runtime.Input.mockImplementationOnce(function () {
      const input = { dispose: vi.fn(), getPrimaryVideoTrack: vi.fn(() => pending.promise) };
      inputs.push(input); return input;
    });
    const videos = moon.createVideoFrames();
    const first = videos.prepare(videoFrame()), second = videos.prepare(videoFrame(700));
    const results = Promise.allSettled([first, second]);
    await vi.waitFor(() => expect(inputs[0]?.getPrimaryVideoTrack).toHaveBeenCalledOnce());
    videos.dispose();
    expect(inputs[0].dispose).toHaveBeenCalledOnce();
    pending.resolve(track);
    const settled = await results;
    expect(settled).toHaveLength(2);
    for (const result of settled) expect(result).toMatchObject({ status: 'rejected', reason: { name: 'AbortError' } });
    expect(fetcher).toHaveBeenCalledOnce();
    expect(inputs[0].dispose).toHaveBeenCalledOnce();
  });

  it('removes a cancelled decoder and permits the following request to retry', async () => {
    const pending = deferred<unknown>();
    decoded.mockImplementationOnce(() => pending.promise);
    const videos = moon.createVideoFrames(), controller = new AbortController();
    const first = videos.prepare(videoFrame(), controller.signal);
    const result = expect(first).rejects.toMatchObject({ name: 'AbortError' });
    await vi.waitFor(() => expect(decoded).toHaveBeenCalledOnce());
    controller.abort();
    expect(inputs[0].dispose).toHaveBeenCalledOnce();
    pending.resolve({ canvas: { width: 128, height: 72 } });
    await result;
    await videos.prepare(videoFrame());
    expect(inputs).toHaveLength(2);
    expect(decoded).toHaveBeenCalledTimes(2);
    videos.dispose();
    expect(inputs.every(input => input.dispose.mock.calls.length === 1)).toBe(true);
  });
});
