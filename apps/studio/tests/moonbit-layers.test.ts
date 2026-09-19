import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { defaultState } from '../shared/model';

const resources = {
  getEquation: () => null,
  measureText: () => ({ width: 50, height: 24, lineHeight: 24, baseline: 18 }),
  preparedImage: (source: string) => source,
  embeddedFontStyles: () => '',
};
const glow = { lost: false };
const item = (id = 'image', source = 'data:image/png;base64,AQ==') => ({
  object: { id, kind: 'image', image: { src: source, width: 64, height: 64 } },
  state: defaultState('image', { width: 64, height: 64 }), writeProgress: 1, order: 'together',
});

describe('MoonBit layer ownership and cache invalidation', () => {
  let moon: typeof import('../../../_build/js/release/build/browser_render/browser_render.js');
  let images: Array<{ onload: (() => void) | null }>;
  let surfaces: Array<{ width: number; height: number; getContext: () => object }>;
  let draw: ReturnType<typeof vi.fn>;

  beforeEach(async () => {
    vi.resetModules();
    moon = await import('../../../_build/js/release/build/browser_render/browser_render.js');
    images = []; surfaces = []; draw = vi.fn();
    vi.stubGlobal('document', { createElement: () => {
      const surface = { width: 300, height: 150, getContext: () => ({ drawImage: draw }) };
      surfaces.push(surface); return surface;
    } });
    vi.stubGlobal('Image', class {
      onload: (() => void) | null = null;
      constructor() { images.push(this); }
      set src(_value: string) {}
    });
    vi.spyOn(URL, 'createObjectURL').mockReturnValue('blob:layer');
    vi.spyOn(URL, 'revokeObjectURL').mockImplementation(() => {});
  });
  afterEach(() => { vi.restoreAllMocks(); vi.unstubAllGlobals(); });

  it('reuses placement-only changes without serializing embedded image data', async () => {
    const cache = moon.createLayerCache(resources);
    const original = item();
    const first = cache.get(original, 1, glow, new AbortController().signal);
    images[0].onload!();
    const layer = await first;
    const stringify = vi.spyOn(JSON, 'stringify');
    const result = await cache.get({ ...original, state: { ...original.state, x: 400, y: 200, opacity: .4, rotation: 33 } }, 1, glow, new AbortController().signal);
    expect(result).toBe(layer);
    expect(stringify).not.toHaveBeenCalled();
    expect(images).toHaveLength(1);
    cache.clear();
    expect(layer.canvas.width).toBe(0);
  });

  for (const action of ['clear', 'retain'] as const) it(`${action} prevents an in-flight layer from being published`, async () => {
    const cache = moon.createLayerCache(resources);
    const pending = cache.get(item(), 1, glow, new AbortController().signal);
    const rejected = expect(pending).rejects.toMatchObject({ name: 'AbortError' });
    if (action === 'clear') cache.clear(); else cache.retain(new Set());
    images[0].onload!();
    await rejected;
    expect(surfaces.every(canvas => canvas.width === 0 && canvas.height === 0)).toBe(true);
    const next = cache.get(item(), 1, glow, new AbortController().signal);
    expect(images).toHaveLength(2);
    images[1].onload!();
    expect((await next).canvas.width).toBeGreaterThan(0);
    cache.clear();
  });

  it('a slower request cannot replace a newer same-ID appearance', async () => {
    const cache = moon.createLayerCache(resources);
    const first = cache.get(item(), 1, glow, new AbortController().signal);
    const rejected = expect(first).rejects.toMatchObject({ name: 'AbortError' });
    const replacement = item('image', 'data:image/png;base64,Ag==');
    const second = cache.get(replacement, 1, glow, new AbortController().signal);
    images[1].onload!();
    const layer = await second;
    images[0].onload!();
    await rejected;
    expect(await cache.get(replacement, 1, glow, new AbortController().signal)).toBe(layer);
    expect(layer.canvas.width).toBeGreaterThan(0);
    expect(surfaces.filter(canvas => canvas.width > 0)).toHaveLength(1);
    cache.clear();
  });

  it('releases a copied raster when drawing itself triggers cancellation', async () => {
    const cache = moon.createLayerCache(resources);
    const controller = new AbortController();
    draw.mockImplementationOnce(() => controller.abort());
    const task = cache.get(item(), 1, glow, controller.signal);
    const rejected = expect(task).rejects.toMatchObject({ name: 'AbortError' });
    images[0].onload!();
    await rejected;
    expect(surfaces.every(canvas => canvas.width === 0 && canvas.height === 0)).toBe(true);
    expect(URL.revokeObjectURL).toHaveBeenCalledExactlyOnceWith('blob:layer');
  });

  it('releases an allocated raster and preserves a native drawing error', async () => {
    const cache = moon.createLayerCache(resources);
    const failure = new Error('native draw failed');
    draw.mockImplementationOnce(() => { throw failure; });
    const task = cache.get(item(), 1, glow, new AbortController().signal);
    const rejected = expect(task).rejects.toBe(failure);
    images[0].onload!();
    await rejected;
    expect(surfaces.every(canvas => canvas.width === 0 && canvas.height === 0)).toBe(true);
  });
});
