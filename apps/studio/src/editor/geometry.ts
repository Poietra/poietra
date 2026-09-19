import type { ObjectState } from '../../shared/model';

export interface Point { x: number; y: number }
export interface Rectangle { x: number; y: number; width: number; height: number }
export type ResizeCorner = 'nw' | 'ne' | 'sw' | 'se';
export const CORNER_SIGNS: Record<ResizeCorner, Point> = {
  nw: { x: -1, y: -1 }, ne: { x: 1, y: -1 }, sw: { x: -1, y: 1 }, se: { x: 1, y: 1 },
};

export { rotateVector, worldToLocal, localToWorld, pointInRotatedBounds, rectangleFromPoints, rectangleContainsRotatedBounds, resizeFromCorner, rotationFromPointer } from '../../../../_build/js/release/build/boundary/boundary.js';
