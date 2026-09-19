import * as moonbit from "../../../../../_build/js/release/build/boundary/boundary.js";
/** Shared dimensions and reveal timing for both SVG and Canvas. */
export const SHAPE_STYLE = {
    minimumArrowHead: 10,
    arrowHeadStrokeWidths: 3,
    arrowHeadSpread: 0.45,
    arrowHeadWriteStart: 0.8,
    numberlineTicks: 11,
    tickHalfLength: 6,
};
export const shapeGeometry = moonbit.shapeGeometry;
export const arrowHeadProgress = moonbit.arrowHeadProgress;
export const numberlineTickProgress = moonbit.numberlineTickProgress;
export const arrowHeadPath = moonbit.arrowHeadPath;
export const numberlineTickPath = moonbit.numberlineTickPath;
