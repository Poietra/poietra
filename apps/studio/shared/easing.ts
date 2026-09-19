import * as moonbit from '../../../_build/js/release/build/boundary/boundary.js';
export type PresetEasing = 'linear' | 'easeInOut' | 'easeIn' | 'easeOut';

/** Unit-square control points for a time (x) → progress (y) curve. */
export interface CubicBezierEasing {
  type: 'cubicBezier';
  x1: number;
  y1: number;
  x2: number;
  y2: number;
}

export type Easing = PresetEasing | CubicBezierEasing;

export const DEFAULT_CUSTOM_EASING: CubicBezierEasing = Object.freeze({ type: 'cubicBezier', x1: 0.25, y1: 0.1, x2: 0.25, y2: 1 });

export function isValidEasing(value: unknown): value is Easing { return moonbit.isValidEasing(value); }
export const easingsEqual: (a: Easing | null | undefined, b: Easing | null | undefined) => boolean = moonbit.easingsEqual;
