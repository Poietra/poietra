import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { loadMathRuntime } from '../src/platform/render-host.mjs';

beforeEach(() => vi.resetModules());
afterEach(() => vi.unstubAllGlobals());
const bindings = () => import('../../../_build/js/release/build/browser_render/browser_render.js');

describe('MoonBit prepared resource ownership', () => {
  it('selects the same bundled Japanese subsets and deduplicates concurrent font requests', async () => {
    const moon = await bindings();
    const require = createRequire(import.meta.url);
    const css = readFileSync(require.resolve('@fontsource/noto-sans-jp/400.css'), 'utf8');
    const files = Object.fromEntries([...css.matchAll(/url\(\.\/files\/([^)]*\.woff2)\)/g)].map(([, name]) => [`/bundled/${name}`, `/font/${name}`]));
    const catalog = moon.createFontCatalog('/inter.woff2', css, files);
    const source = '漢字 あいうえお 한국어 😀 abc Ω';
    const points = [...source].map(c => c.codePointAt(0)!);
    const expected = new Set(['/inter.woff2']);
    for (const [, declaration] of css.matchAll(/@font-face\s*\{([^}]+)\}/g)) {
      const name = /url\(\.\/files\/([^)]*\.woff2)\)/.exec(declaration)?.[1];
      const ranges = /unicode-range:\s*([^;]+);/.exec(declaration)?.[1];
      if (!name || !ranges) continue;
      if (ranges.split(',').some(range => {
        const [start, end = start] = range.trim().slice(2).split('-').map(value => parseInt(value, 16));
        return points.some(point => point > 255 && point >= start && point <= end);
      })) expected.add(`/font/${name}`);
    }
    const installed = vi.fn();
    vi.stubGlobal('document', { fonts: { add: installed } });
    vi.stubGlobal('FontFace', class { load() { return Promise.resolve(this); } });
    const fetcher = vi.fn(async () => ({ ok: true, arrayBuffer: async () => new Uint8Array([1, 2, 3, 4]).buffer }));
    vi.stubGlobal('fetch', fetcher);
    await Promise.all(Array.from({ length: 3 }, () => moon.prepareFonts([source], async () => catalog)));
    expect(new Set(fetcher.mock.calls.map(args => (args as unknown as [string])[0]))).toEqual(expected);
    expect(fetcher).toHaveBeenCalledTimes(expected.size);
    expect(installed).toHaveBeenCalledTimes(expected.size);
    const embedded = moon.embeddedFontStyles([source]);
    expect(embedded).toContain('data:font/woff2;base64,AQIDBA==');
    expect((embedded.match(/@font-face/g) ?? []).length).toBe(expected.size);
    expect(moon.embeddedFontStyles(['abc']).match(/@font-face/g)).toHaveLength(1);
    expect(moon.embeddedFontStyles([''])).toBe('');
  });

  it.each(['synchronous throw', 'rejected request', 'HTTP error', 'font load failure'] as const)('retries fonts after a %s without publishing incomplete resources', async failure => {
    const moon = await bindings();
    const catalog = moon.createFontCatalog('/font', '', {});
    const installed = vi.fn();
    let fail = true;
    vi.stubGlobal('document', { fonts: { add: installed } });
    vi.stubGlobal('FontFace', class { load() { return fail && failure === 'font load failure' ? Promise.reject(new Error('font')) : Promise.resolve(this); } });
    const fetcher = vi.fn(() => {
      if (fail && failure === 'synchronous throw') throw new Error('offline');
      if (fail && failure === 'rejected request') return Promise.reject(new Error('offline'));
      return Promise.resolve({ ok: !fail || failure !== 'HTTP error', arrayBuffer: async () => new Uint8Array([0]).buffer });
    });
    vi.stubGlobal('fetch', fetcher);
    await expect(moon.prepareFonts(['a'], async () => catalog)).rejects.toThrow(failure === 'HTTP error' ? 'Font asset could not be loaded: Poietra Inter' : failure === 'font load failure' ? 'font' : 'offline');
    expect(moon.embeddedFontStyles(['a'])).toBe('');
    expect(installed).not.toHaveBeenCalled();
    fail = false;
    await moon.prepareFonts(['a'], async () => catalog);
    expect(fetcher).toHaveBeenCalledTimes(2);
    expect(installed).toHaveBeenCalledTimes(1);
    expect(moon.embeddedFontStyles(['a'])).toContain('@font-face');
  });

  it('retries failed MathJax loading and retains a stable immutable equation shared by callers', async () => {
    const moon = await bindings();
    await expect(moon.prepareEquations(['x^2'], () => { throw new Error('chunk unavailable'); })).rejects.toThrow('chunk unavailable');
    const load = vi.fn(loadMathRuntime);
    await Promise.all([moon.prepareEquations(['x^2', 'x^2'], load), moon.prepareEquations(['x^2'], load)]);
    expect(load).toHaveBeenCalledTimes(1);
    const equation = moon.getEquation('x^2');
    expect(equation.glyphs).toBeGreaterThan(0);
    expect(moon.getEquation('x^2')).toBe(equation);
    expect(Object.isFrozen(equation)).toBe(true);
    expect(Object.isFrozen(equation.tree.children)).toBe(true);
    expect(Object.isFrozen(equation.tree.children[0].attributes)).toBe(true);
    await moon.prepareEquations(['x^2'], load);
    expect(load).toHaveBeenCalledTimes(1);
  });
});
