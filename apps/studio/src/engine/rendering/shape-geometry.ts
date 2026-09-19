import type { RenderObject } from '../evaluate';
import * as moonbit from '../../../../../_build/js/release/build/boundary/boundary.js';

/** Shared dimensions and reveal timing for both SVG and Canvas. */
export const SHAPE_STYLE = {
  minimumArrowHead: 10,
  arrowHeadStrokeWidths: 3,
  arrowHeadSpread: 0.45,
  arrowHeadWriteStart: 0.8,
  numberlineTicks: 11,
  tickHalfLength: 6,
} as const;

export type ShapeGeometry =
  | { kind: 'circle'; radiusX: number; radiusY: number }
  | { kind: 'rectangle'; width: number; height: number; radius: number }
  | { kind: 'path'; path: string }
  | { kind: 'arrow' | 'numberline'; length: number; angle: number; head: number; spread: number };

export const shapeGeometry: (item: RenderObject) => ShapeGeometry | null = moonbit.shapeGeometry;
export const arrowHeadProgress: (progress: number) => number = moonbit.arrowHeadProgress;
export const numberlineTickProgress: (progress: number, index: number) => number = moonbit.numberlineTickProgress;
export const arrowHeadPath: (shape: Extract<ShapeGeometry, { kind: 'arrow' | 'numberline' }>) => string = moonbit.arrowHeadPath;
export const numberlineTickPath: (length: number, index: number) => string = moonbit.numberlineTickPath;
