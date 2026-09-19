import type { RenderObject } from '../evaluate';
import { shapeGeometry } from './shape-geometry';
import { prepareShapeDrawing as moonPrepareShape } from '../../../../../_build/js/release/build/browser_render/browser_render.js';

export interface ShapeDrawing {
  readonly key: string;
  /** Logical geometry source bytes; Path2D's internal allocation is not measurable. */
  readonly sourceBytes: number;
  /** Draw in local Scene coordinates; the caller applies bounds and output scaling. */
  paint(context: CanvasRenderingContext2D, item: RenderObject): void;
}

export function prepareShapeDrawing(item: RenderObject, previous?: ShapeDrawing): ShapeDrawing | null {
  return moonPrepareShape(shapeGeometry(item), previous);
}
