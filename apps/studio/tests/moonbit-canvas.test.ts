import { afterEach, describe, expect, it, vi } from 'vitest';
import * as canvas from '../../../_build/js/release/build/browser_render/browser_render.js';
import { equationMarkup } from '../../../_build/js/release/build/boundary/boundary.js';
import { defaultState } from '../shared/model';

afterEach(() => { vi.unstubAllGlobals(); vi.restoreAllMocks(); });

function nativeDrawing() {
  const allocated = vi.fn();
  vi.stubGlobal('Path2D', class { constructor(source?: string) { allocated(source); } ellipse() {} closePath() {} rect() {} });
  vi.stubGlobal('DOMMatrix', class { a = 1; b = 0; c = 0; d = 1; e = 0; f = 0; multiply() { return this; } });
  vi.stubGlobal('document', { createElementNS: () => ({ setAttribute() {}, getTotalLength: () => 100 }) });
  return allocated;
}

// MathJax emits only `translate`/`scale`, so the stub parses just those.
class Matrix {
  a = 1; b = 0; c = 0; d = 1; e = 0; f = 0;
  static of(a: number, b: number, c: number, d: number, e: number, f: number) { return Object.assign(new Matrix(), { a, b, c, d, e, f }); }
  multiply(o: Matrix) { return Matrix.of(this.a * o.a + this.c * o.b, this.b * o.a + this.d * o.b, this.a * o.c + this.c * o.d, this.b * o.c + this.d * o.d, this.a * o.e + this.c * o.f + this.e, this.b * o.e + this.d * o.f + this.f); }
  translate(x: number, y = 0) { return this.multiply(Matrix.of(1, 0, 0, 1, x, y)); }
  scale(x: number, y = x) { return this.multiply(Matrix.of(x, 0, 0, y, 0, 0)); }
}

function nativeTransforms() {
  vi.stubGlobal('Path2D', class { ellipse() {} closePath() {} rect() {} });
  vi.stubGlobal('DOMMatrix', Matrix);
  vi.stubGlobal('document', { createElementNS: () => {
    let source = '';
    return {
      setAttribute(name: string, value: string) { if (name === 'transform') source = value; },
      getTotalLength: () => 100,
      get transform() {
        const matrix = [...source.matchAll(/(translate|scale)\(\s*(-?[\d.]+)(?:[\s,]+(-?[\d.]+))?\s*\)/g)]
          .reduce((m, [, op, x, y]) => op === 'translate'
            ? m.translate(Number(x), y === undefined ? 0 : Number(y))
            : m.scale(Number(x), y === undefined ? Number(x) : Number(y)), new Matrix());
        return { baseVal: { consolidate: () => ({ matrix }) } };
      },
    };
  } });
}

function recordingContext() {
  const calls = { transform: vi.fn(), rect: vi.fn() };
  return { ...calls, context: { globalAlpha: 1, save() {}, restore() {}, beginPath() {}, clip() {}, fill() {}, setLineDash() {}, ...calls } };
}

describe('MoonBit Canvas resource lifetime', () => {
  it('captures only render values before awaiting and keeps the caller frame independent', async () => {
    const draw = vi.fn();
    const context = { save() {}, restore() {}, resetTransform() {}, fillRect() {}, drawImage: draw, globalAlpha: 1 };
    const surface = () => ({ width: 640, height: 360, getContext: (kind: string) => kind === '2d' ? context : null });
    vi.stubGlobal('document', { createElement: surface });
    vi.stubGlobal('Image', class {
      onload: (() => void) | null = null;
      set src(value: string) { if (value) queueMicrotask(() => this.onload?.()); }
    });
    const blobs: Blob[] = [];
    vi.spyOn(URL, 'createObjectURL').mockImplementation(blob => { blobs.push(blob as Blob); return 'blob:captured-frame'; });
    vi.spyOn(URL, 'revokeObjectURL').mockImplementation(() => {});
    const clone = vi.spyOn(globalThis, 'structuredClone');
    const painter = await canvas.createFramePainter(surface(), {
      getEquation: () => null, measureText: () => ({ width: 1, height: 1, lineHeight: 1, baseline: 1 }),
      preparedImage: () => undefined, embeddedFontStyles: () => '',
    });
    const state = defaultState('circle', { x: 41, fill: '#123456' });
    const frame = { width: 640, height: 360, background: '#08090b', objects: [
      { object: { id: 'circle', kind: 'circle' }, state, writeProgress: 1, order: 'together' },
    ] };
    // Domain-unrelated metadata must not be traversed or copied by the painter.
    Object.defineProperty(frame, 'extension', { enumerable: true, get() { throw new Error('unused extension'); } });
    try {
      const pending = painter.render(frame);
      state.x = 900;
      state.fill = '#abcdef';
      frame.objects.length = 0;
      frame.width = 900;
      await pending;
      const svg = await blobs[0].text();
      expect(svg).toContain('translate(41 ');
      expect(svg).toContain('#123456');
      expect(svg).toContain('viewBox="0 0 640 360"');
      expect(svg).not.toContain('#abcdef');
      expect(frame.objects).toEqual([]);
      expect(clone).not.toHaveBeenCalled();
      expect(draw).toHaveBeenCalledTimes(2);
    } finally { painter.dispose(); }
  });

  it('reuses prepared paths across appearance changes and replaces changed geometry', () => {
    const allocated = nativeDrawing();
    const geometry = { kind: 'numberline', length: 200, angle: 0, head: 10, spread: 4.5 };
    const first = canvas.prepareShapeDrawing(geometry, undefined);
    expect(first).not.toBeNull();
    expect(allocated).toHaveBeenCalledTimes(13);
    for (let i = 0; i < 100; i++) expect(canvas.prepareShapeDrawing({ ...geometry }, first)).toBe(first);
    expect(allocated).toHaveBeenCalledTimes(13);
    const changed = canvas.prepareShapeDrawing({ ...geometry, length: 300 }, first);
    expect(changed).not.toBe(first);
    expect(allocated).toHaveBeenCalledTimes(26);
  });

  it('restores the native Canvas after a shape paint failure and preserves the original error', () => {
    nativeDrawing();
    const drawing = canvas.prepareShapeDrawing({ kind: 'circle', radiusX: 20, radiusY: 30 }, undefined);
    const failure = new Error('canvas interrupted');
    const context = { globalAlpha: .7, save: vi.fn(), restore: vi.fn(), fill: vi.fn(() => { throw failure; }) };
    expect(() => drawing.paint(context, { writeProgress: .5, state: { fill: '#abc', stroke: 'none', strokeWidth: 0 } })).toThrow(failure);
    expect(context.save).toHaveBeenCalledTimes(1);
    expect(context.restore).toHaveBeenCalledTimes(1);
  });

  it('unwinds both equation and glyph scopes when a browser stroke operation fails', () => {
    nativeDrawing();
    const equation = { glyphs: 1, tree: { tag: 'g', attributes: {}, children: [{ tag: 'path', attributes: { d: 'M0 0H10' }, children: [] }] } };
    const drawing = canvas.prepareEquationDrawing(equation);
    expect(drawing?.glyphCount).toBe(1);
    const failure = new Error('stroke interrupted');
    const context = { globalAlpha: 1, save: vi.fn(), restore: vi.fn(), transform() {}, setLineDash() {}, stroke: vi.fn(() => { throw failure; }) };
    expect(() => drawing.paint(context, .3, 'sequential', '#abc')).toThrow(failure);
    expect(context.save).toHaveBeenCalledTimes(2);
    expect(context.restore).toHaveBeenCalledTimes(2);
  });

  // Real mathjax-full 3.2.2 markup for `\left|...\right|`: a stretched delimiter
  // nests its own `<svg>` viewport, which Canvas2D has no equivalent for.
  it('replaces a stretched delimiter viewport with the equivalent canvas transform', () => {
    nativeTransforms();
    const bar = { tag: 'path', attributes: { d: 'M139 -249H137V251L120 737Q152 750 159 735V-235Z' }, children: [] };
    const viewport = { tag: 'svg', attributes: { width: '278', height: '1267.9', y: '-383.9', x: '27.5', viewBox: '0 -157.1 278 1267.9' }, children: [bar] };
    const drawing = canvas.prepareEquationDrawing({ glyphs: 1, tree: { tag: 'g', attributes: {}, children: [viewport] } });
    // The viewport wraps the glyph; it is not a glyph itself.
    expect(drawing?.glyphCount).toBe(1);
    const { context, transform, rect } = recordingContext();
    drawing.paint(context, 1, 'together', '#abc');
    expect(transform.mock.calls).toEqual([[1, 0, 0, 1, 27.5, expect.closeTo(-226.8, 9)]]);
    expect(rect.mock.calls).toEqual([[27.5, -383.9, 278, 1267.9]]);
    // A viewport without a usable viewBox keeps the SVG fallback.
    const broken = { ...viewport, attributes: { ...viewport.attributes, viewBox: '0 -157.1 0 1267.9' } };
    expect(canvas.prepareEquationDrawing({ glyphs: 1, tree: { tag: 'g', attributes: {}, children: [broken] } })).toBeNull();
  });

  // Real mathjax-full 3.2.2 markup for `\overline{ab}`. Unlike a delimiter, a
  // stretched rule overflows its viewport: the glyph spans 2.874 x 499 = 1434
  // units where the viewport shows 958, so both renderers must clip it.
  it('clips a stretched rule to the same region in SVG and on canvas', () => {
    nativeTransforms();
    const rule = { tag: 'path', attributes: { d: 'M0 248V285H499V248H0Z', transform: 'scale(2.874,1)' }, children: [] };
    const viewport = { tag: 'svg', attributes: { width: '958', height: '237', x: '0', y: '148', viewBox: '239.5 148 958 237' }, children: [rule] };
    const tree = { tag: 'g', attributes: { 'stroke-width': '0', transform: 'scale(1,-1)' }, children: [
      { tag: 'g', attributes: {}, children: [
        { tag: 'g', attributes: {}, children: [{ tag: 'path', attributes: { d: 'M0 0H10' }, children: [] }] },
        { tag: 'g', attributes: { transform: 'translate(0,626)' }, children: [viewport] },
      ] },
    ] };
    const equation = { x: 0, y: -1011, width: 958, height: 1022, tree, glyphs: 2 };
    const drawing = canvas.prepareEquationDrawing(equation);
    expect(drawing?.glyphCount).toBe(2);
    const { context, transform, rect } = recordingContext();
    drawing.paint(context, 1, 'together', '#abc');
    // Only the rule is clipped, and to the viewport's own region: scale(1,-1)
    // then translate(0,626) maps y 148..385 to -1011..-774.
    expect(rect.mock.calls).toEqual([[0, -1011, 958, 237]]);
    expect(transform.mock.calls).toEqual([[1, 0, 0, -1, 0, 0], [2.874, 0, 0, -1, -239.5, -626]]);
    // SVG keeps the nested viewport itself, under the same two transforms.
    const markup = equationMarkup(equation, 1, 'together');
    expect(markup).toContain('<g stroke-width="0" transform="scale(1,-1)">');
    expect(markup).toContain('<g transform="translate(0,626)"><svg width="958" height="237" x="0" y="148" viewBox="239.5 148 958 237">');
  });

  // Disjoint nested viewports show nothing in SVG; a negative canvas extent
  // would reverse the clip rectangle and draw the glyph in full instead.
  it('clips disjoint nested viewports to an empty region', () => {
    nativeTransforms();
    const glyph = { tag: 'path', attributes: { d: 'M-30 -30H70V70H-30Z' }, children: [] };
    const outer = { width: '20', height: '20', viewBox: '0 0 20 20' };
    const nested = (attributes: Record<string, string>) => ({
      tag: 'svg', attributes: outer, children: [{ tag: 'svg', attributes: { ...outer, ...attributes }, children: [glyph] }],
    });
    for (const [attributes, expected] of [
      [{ x: '30' }, [30, 0, 0, 20]],
      [{ y: '30' }, [0, 30, 20, 0]],
    ] as const) {
      const equation = { glyphs: 1, tree: { tag: 'g', attributes: {}, children: [nested(attributes)] } };
      const drawing = canvas.prepareEquationDrawing(equation);
      const { context, rect } = recordingContext();
      drawing.paint(context, 1, 'together', '#abc');
      expect(rect.mock.calls).toEqual([expected]);
      // The SVG renderer nests the same empty viewports.
      expect(equationMarkup({ x: 0, y: 0, width: 20, height: 20, ...equation }, 1, 'together')).toContain(`<svg ${Object.entries({ ...outer, ...attributes }).map(([k, v]) => `${k}="${v}"`).join(' ')}>`);
    }
  });

  it('keeps SVG fallback for unsupported equation primitives and unavailable native APIs', () => {
    nativeDrawing();
    const tree = { tag: 'g', attributes: {}, children: [{ tag: 'circle', attributes: { r: '20' }, children: [] }] };
    expect(canvas.prepareEquationDrawing({ glyphs: 1, tree })).toBeNull();
    expect(canvas.prepareEquationDrawing({ glyphs: 2049, tree })).toBeNull();
    vi.stubGlobal('Path2D', undefined);
    expect(canvas.prepareShapeDrawing({ kind: 'circle', radiusX: 20, radiusY: 20 }, undefined)).toBeNull();
  });

  it('shapes each full text line once for a sequential atlas and makes disposal idempotent', async () => {
    const measurements = vi.fn(() => ({ width: 50, actualBoundingBoxLeft: 0, actualBoundingBoxRight: 50, actualBoundingBoxAscent: 16, actualBoundingBoxDescent: 4 }));
    const draw = vi.fn();
    const surfaces: Array<{ width: number; height: number; getContext: () => object }> = [];
    vi.stubGlobal('document', { createElement: () => {
      const surface = { width: 300, height: 150, getContext: () => ({ font: '', textRendering: '', measureText: measurements, drawImage: draw }) };
      surfaces.push(surface);
      return surface;
    } });
    vi.stubGlobal('Image', class {
      onload: (() => void) | null = null;
      set src(value: string) { if (value) queueMicrotask(() => this.onload?.()); }
    });
    vi.spyOn(URL, 'createObjectURL').mockReturnValue('blob:text-atlas');
    const revoke = vi.spyOn(URL, 'revokeObjectURL').mockImplementation(() => {});
    const item = { object: { id: 'text', kind: 'text' }, state: defaultState('text', { text: 'A B\n日本', fontSize: 20 }), order: 'sequential', writeProgress: .5 };
    const drawing = await canvas.prepareTextDrawing(item, 1, 1024 * 1024, new AbortController().signal);
    expect(drawing).not.toBeNull();
    expect(measurements).toHaveBeenCalledTimes(2);
    expect(surfaces).toHaveLength(4);
    expect(revoke).toHaveBeenCalledExactlyOnceWith('blob:text-atlas');
    drawing.dispose(); drawing.dispose();
    expect(surfaces.slice(1).every(surface => surface.width === 0 && surface.height === 0)).toBe(true);
    const native = { save: vi.fn() };
    drawing.paint(native, item);
    expect(native.save).not.toHaveBeenCalled();
  });
});
