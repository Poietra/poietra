export interface Point {
    x: number;
    y: number;
}
export interface Rectangle {
    x: number;
    y: number;
    width: number;
    height: number;
}
export type ResizeCorner = 'nw' | 'ne' | 'sw' | 'se';
export declare const CORNER_SIGNS: Record<ResizeCorner, Point>;
export { rotateVector, worldToLocal, localToWorld, pointInRotatedBounds, rectangleFromPoints, rectangleContainsRotatedBounds, resizeFromCorner, rotationFromPointer } from '../../../../_build/js/release/build/boundary/boundary.js';
