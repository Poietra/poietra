import type { RenderObject } from '../evaluate';
export interface ShapeDrawing {
    readonly key: string;
    /** Logical geometry source bytes; Path2D's internal allocation is not measurable. */
    readonly sourceBytes: number;
    /** Draw in local Scene coordinates; the caller applies bounds and output scaling. */
    paint(context: CanvasRenderingContext2D, item: RenderObject): void;
}
export declare function prepareShapeDrawing(item: RenderObject, previous?: ShapeDrawing): ShapeDrawing | null;
