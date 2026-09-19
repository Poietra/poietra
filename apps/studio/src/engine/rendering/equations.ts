import * as moonbit from '../../../../../_build/js/release/build/boundary/boundary.js';
import * as resources from '../../../../../_build/js/release/build/browser_render/browser_render.js';
import { loadMathRuntime } from '../../platform/render-host.mjs';
export const EQUATION_UNITS_PER_EM = 1000;
export const EQUATION_WRITE_STROKE_UNITS = 18;
interface MathNode { tag: string; attributes: Record<string, string>; children: MathNode[] }
export interface Equation { width: number; height: number; x: number; y: number; tree: MathNode; glyphs: number }

export function prepareEquations(sources: string[]): Promise<void> { return resources.prepareEquations(sources, loadMathRuntime); }
export const getEquation: (source: string) => Equation | null = resources.getEquation;
export const equationGlyphProgress: (progress: number, order: 'together' | 'sequential', glyphs: number, index: number) => number = moonbit.equationGlyphProgress;
export const equationFillProgress: (progress: number) => number = moonbit.equationFillProgress;
export const equationMarkup: (equation: Equation, progress: number, order: 'together' | 'sequential') => string = moonbit.equationMarkup;
