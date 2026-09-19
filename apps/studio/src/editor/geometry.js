export const CORNER_SIGNS = {
    nw: { x: -1, y: -1 }, ne: { x: 1, y: -1 }, sw: { x: -1, y: 1 }, se: { x: 1, y: 1 },
};
export { rotateVector, worldToLocal, localToWorld, pointInRotatedBounds, rectangleFromPoints, rectangleContainsRotatedBounds, resizeFromCorner, rotationFromPointer } from "../../../../_build/js/release/build/boundary/boundary.js";
