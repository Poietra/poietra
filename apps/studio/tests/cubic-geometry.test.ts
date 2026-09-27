import { expect, it } from 'vitest';
import { defaultState } from '../shared/model';
import { shapeGeometry } from '../src/engine/rendering/shape-geometry';
import { number as n } from '../src/engine/rendering/svg';

it('the public shape adapter keeps cubic coordinates in the existing path-string contract', () => {
  for (const value of [0, -0, 0.0000001, -0.0000005, 1.23456789, -1.23456789, 99999999999999.98, 999999999999999.9, 1e15, 1e300, NaN, Infinity, -Infinity]) {
    const state = defaultState('path', { width: value, height: -value, path: { c1: { x: value, y: -value }, c2: { x: -value, y: value } } });
    expect(shapeGeometry({ object: { id: 'curve', name: 'Curve', kind: 'path', order: 0, groupId: null, locked: false }, state, writeProgress: 1, order: 'together' })).toEqual({ kind: 'path', path: `M0 0 C${n(value)} ${n(-value)} ${n(-value)} ${n(value)} ${n(value)} ${n(-value)}` });
  }
});
