import { createFramePainter } from "./painter.js";
import { prepareScene } from "./renderer.js";
import * as moonbit from "../../../../_build/js/release/build/browser_export/browser_export.js";
export { getExportCapabilities } from "./exporting/codecs.js";
const host = { createFramePainter, prepareScene };
export function exportScene(scene, kernel, options) {
    return moonbit.exportScene(scene, kernel, options, host);
}
export function exportProject(project, kernel, options) {
    return moonbit.exportProject(project, kernel, options, host);
}
