import { describe, expect, it } from 'vitest';
import { defaultState, type ObjectKind } from '../shared/model';
import { makeDemoProject } from '../shared/demo';
import type { RenderObject } from '../src/engine/evaluate';
import { compositionFrame } from '../src/engine/evaluate';
import * as current from '../src/engine/renderer';
import * as previous from './oracle/rendering/renderer';
import * as svg from '../src/engine/rendering/svg';
import * as oldSvg from './oracle/rendering/svg';
import * as geometry from '../src/engine/rendering/shape-geometry';
import * as oldGeometry from './oracle/rendering/shape-geometry';

describe('compiled MoonBit rendering parity', () => {
  it('preserves XML escaping and collision-free IDs across every UTF-16 code unit', () => {
    const allUnits = Array.from({ length: 65536 }, (_, i) => String.fromCharCode(i)).join('|');
    for (const source of [allUnits, 'a😀𠮷b', '\ud800\ud800\udc00\udc00', '<&"\'日本語\n\t', '']) {
      expect(svg.escapeXml(source)).toBe(oldSvg.escapeXml(source));
      expect(svg.safeId(source)).toBe(oldSvg.safeId(source));
    }
  });

  it('preserves literal paint filtering and finite number formatting', () => {
    const colors = ['none', 'red', '#abc', '#1234', '#123456', '#12345678', 'currentColor', 'inherit', 'initial', 'unset', 'revert', 'revert-layer', 'url(#a)', 'var(--a)', 'rgb(1 2 3 / .5)', 'rgba( 1, 2, 3, 0.5 )', 'hsl(+1 -2% 3%)', 'rgb()', 'rgb(a)', 'RED', 'rgb(1\u00852)', 'rgb(1\u30002)', 'rgb(1\n2)', '#abcdz', 'red" onload="x'];
    for (const color of colors) for (const space of ['', ' ', '\t', '\ufeff', '\u3000']) {
      expect(svg.color(space + color + space, 'fallback')).toBe(oldSvg.color(space + color + space, 'fallback'));
    }
    for (const value of [NaN, Infinity, -Infinity, -0, 0, .8, .55, 1, -.0000005, .0000005, 1e14 + .5, 1e15, 1e21, Number.MIN_VALUE, Number.MAX_VALUE]) {
      expect(svg.finite(value)).toBe(oldSvg.finite(value));
      expect(svg.finite(value, 42)).toBe(oldSvg.finite(value, 42));
      expect(svg.unit(value)).toBe(oldSvg.unit(value));
      expect(svg.number(value)).toBe(oldSvg.number(value));
    }
  });

  it('matches shapes, exact cubic extrema and complete SVG across seeded frames', () => {
    let seed = 1234567;
    const random = () => ((seed = Math.imul(seed, 1664525) + 1013904223 | 0) >>> 0) / 4294967296;
    const coordinate = () => (random() - .5) * 1500;
    const kinds: ObjectKind[] = ['circle', 'rectangle', 'path', 'arrow', 'numberline', 'text', 'equation', 'image', 'video'];
    for (let sample = 0; sample < 100; sample++) {
      const objects: RenderObject[] = kinds.map((kind, i) => ({
        object: { id: `${kind}/<&😀`, name: kind, kind, order: i, groupId: null, locked: false, image: kind === 'image' ? { src: 'data:image/png;base64,iVBORw0KGgo=', width: 1, height: 1 } : undefined },
        state: defaultState(kind, { x: coordinate(), y: coordinate(), width: coordinate(), height: coordinate(), rotation: coordinate(), opacity: random(), cornerRadius: random() * 80, strokeWidth: random() * 8, fontSize: random() * 100, text: '日本語 A😀&\n é  j', path: { c1: { x: coordinate(), y: coordinate() }, c2: { x: coordinate(), y: coordinate() } }, effect: sample % 2 ? 'glow' : 'none' }),
        writeProgress: sample % 5 === 0 ? 1 : random(), order: sample % 2 ? 'together' : 'sequential', videoFrame: kind === 'video' ? 'data:image/png;base64,iVBORw0KGgo=' : undefined,
      }));
      for (const item of objects) {
        expect(geometry.shapeGeometry(item)).toEqual(oldGeometry.shapeGeometry(item));
        expect(current.objectBounds(item)).toEqual(previous.objectBounds(item));
      }
      const frame = { objects, width: 1280, height: 720, background: '#08090b' };
      const options = { idPrefix: `differential-${sample}`, background: sample % 2 === 0 };
      expect(current.frameToSvg(frame, options)).toBe(previous.frameToSvg(frame, options));
    }
  });

  it('matches prepared MathJax glyphs, fallback text and partial Write output', async () => {
    const scene = makeDemoProject().scenes['scene-1'];
    await Promise.all([current.prepareScene(scene), previous.prepareScene(scene)]);
    for (const id of scene.compositionOrder) {
      const frame = compositionFrame(scene, scene.compositions[id]);
      for (const progress of [0, .001, .2, .55, .8, .99, 1]) for (const order of ['together', 'sequential'] as const) {
        const authored = { ...frame, objects: frame.objects.map(item => ({ ...item, writeProgress: progress, order })) };
        const options = { idPrefix: `${id}-${order}-${progress}` };
        for (const item of authored.objects) expect(current.objectBounds(item)).toEqual(previous.objectBounds(item));
        expect(current.frameToSvg(authored, options)).toBe(previous.frameToSvg(authored, options));
      }
    }
  });
});
