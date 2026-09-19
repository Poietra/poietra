import { shapeGeometry } from "./shape-geometry.js";
import { prepareShapeDrawing as moonPrepareShape } from "../../../../../_build/js/release/build/browser_render/browser_render.js";
export function prepareShapeDrawing(item, previous) {
    return moonPrepareShape(shapeGeometry(item), previous);
}
