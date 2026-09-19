import { afterEach, describe, expect, it, vi } from 'vitest';
import * as canvas from '../../../_build/js/release/build/browser_render/browser_render.js';
import { defaultState } from '../shared/model';

afterEach(() => { vi.unstubAllGlobals(); vi.restoreAllMocks(); });

function nativeDrawing() {
  const allocated = vi.fn();
  vi.stubGlobal('Path2D', class { constructor(source?: string) { allocated(source); } ellipse() {} closePath() {} rect() {} });
  vi.stubGlobal('DOMMatrix', class { a = 1; b = 0; c = 0; d = 1; e = 0; f = 0; multiply() { return this; } });
  vi.stubGlobal('document', { createElementNS: () => ({ setAttribute() {}, getTotalLength: () => 100 }) });
  return allocated;
}

describe('MoonBit Canvas resource lifetime', () => {
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
