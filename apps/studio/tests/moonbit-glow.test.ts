import { afterEach, describe, expect, it, vi } from 'vitest';
import { createGlowRenderer } from '../src/engine/effects/glow';

function graphics(failure = '') {
  const live = new Set<object>();
  const removed: object[] = [];
  const allocate = (kind: string) => {
    if (failure === `allocate:${kind}`) return null;
    const value = { kind }; live.add(value); return value;
  };
  const remove = (value: object) => { expect(live.delete(value)).toBe(true); removed.push(value); };
  const broken = (method: string, fallback?: unknown) => (..._args: unknown[]) => {
    if (failure === method) throw new Error(method);
    return fallback;
  };
  const lose = vi.fn();
  const canvas = { width: 300, height: 150, addEventListener: vi.fn(), removeEventListener: vi.fn(), getContext: () => gl };
  const gl = new Proxy({
    createTexture: () => allocate('texture'), createFramebuffer: () => allocate('framebuffer'),
    createShader: () => allocate('shader'), createProgram: () => allocate('program'),
    deleteTexture: remove, deleteFramebuffer: remove, deleteShader: remove, deleteProgram: remove,
    isContextLost: () => false, getExtension: () => ({ loseContext: lose }),
    getParameter: (name: string) => name === 'MAX_TEXTURE_SIZE' ? 8192 : new Int32Array([8192, 8192]),
    getShaderParameter: () => failure !== 'compile', getProgramParameter: () => failure !== 'link',
    getShaderInfoLog: () => 'broken shader', getProgramInfoLog: () => 'broken link',
    getUniformLocation: () => failure === 'uniform' ? null : {},
    getError: () => 0, checkFramebufferStatus: () => 'FRAMEBUFFER_COMPLETE',
    get drawingBufferWidth() { return canvas.width; }, get drawingBufferHeight() { return canvas.height; },
  }, { get(target, name: string) {
    if (name in target) return Reflect.get(target, name);
    return /^[A-Z_0-9]+$/.test(name) ? name : broken(name);
  } });
  vi.stubGlobal('document', { createElement: () => canvas });
  return { live, removed, canvas, lose };
}
afterEach(() => vi.unstubAllGlobals());

describe('MoonBit GPU resource ownership', () => {
  for (const failure of ['allocate:texture', 'allocate:framebuffer', 'allocate:shader', 'allocate:program',
    'texParameteri', 'framebufferTexture2D', 'shaderSource', 'compileShader', 'compile', 'attachShader',
    'linkProgram', 'link', 'uniform', 'disable']) {
    it(`releases every acquired resource when initialization fails at ${failure}`, () => {
      const fake = graphics(failure);
      expect(createGlowRenderer()).toBeNull();
      expect(fake.live.size).toBe(0);
      expect(fake.canvas.width).toBe(0);
      expect(fake.canvas.height).toBe(0);
      expect(fake.lose).toHaveBeenCalledOnce();
      expect(fake.canvas.removeEventListener).toHaveBeenCalledOnce();
    });
  }

  it('keeps completed resources alive until disposal and rejects use after disposal', () => {
    const fake = graphics();
    const renderer = createGlowRenderer()!;
    expect(renderer).not.toBeNull();
    expect(fake.live.size).toBe(7);
    expect(fake.removed).toHaveLength(4); // Temporary shader handles.
    renderer.dispose(); renderer.dispose();
    expect(fake.live.size).toBe(0);
    expect(fake.removed).toHaveLength(11);
    expect(fake.lose).toHaveBeenCalledOnce();
    expect(() => renderer.render({} as TexImageSource, 1, 1, 0)).toThrow('disposed');
    expect(renderer.lost).toBe(true);
  });

  it('preserves native upload failures and releases the owned resources afterward', () => {
    const fake = graphics('texSubImage2D');
    const renderer = createGlowRenderer()!;
    expect(() => renderer.render({} as TexImageSource, 16, 16, 4)).toThrow('texSubImage2D');
    renderer.dispose();
    expect(fake.live.size).toBe(0);
  });
});
