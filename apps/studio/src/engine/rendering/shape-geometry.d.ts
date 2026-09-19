import type { RenderObject } from '../evaluate';
/** Shared dimensions and reveal timing for both SVG and Canvas. */
export declare const SHAPE_STYLE: {
    readonly minimumArrowHead: 10;
    readonly arrowHeadStrokeWidths: 3;
    readonly arrowHeadSpread: 0.45;
    readonly arrowHeadWriteStart: 0.8;
    readonly numberlineTicks: 11;
    readonly tickHalfLength: 6;
};
export type ShapeGeometry = {
    kind: 'circle';
    radiusX: number;
    radiusY: number;
} | {
    kind: 'rectangle';
    width: number;
    height: number;
    radius: number;
} | {
    kind: 'path';
    path: string;
} | {
    kind: 'arrow' | 'numberline';
    length: number;
    angle: number;
    head: number;
    spread: number;
};
export declare const shapeGeometry: (item: RenderObject) => ShapeGeometry | null;
export declare const arrowHeadProgress: (progress: number) => number;
export declare const numberlineTickProgress: (progress: number, index: number) => number;
export declare const arrowHeadPath: (shape: Extract<ShapeGeometry, {
    kind: 'arrow' | 'numberline';
}>) => string;
export declare const numberlineTickPath: (length: number, index: number) => string;
