import { createFramePainter } from "./painter.js";
import { prepareScene } from "./renderer.js";
const host = { createFramePainter, prepareScene };
const runtime = () => import("../../../../_build/js/release/build/browser_export/browser_export.js");
export async function getExportCapabilities() {
    return (await runtime()).getExportCapabilities();
}
// Capture native inputs before loading the encoder; edits during that await
// must not alter an export that has already started.
export async function exportScene(scene, kernel, options) {
    const source = structuredClone(scene), settings = { ...options };
    return (await runtime()).exportScene(source, kernel, settings, host);
}
export async function exportProject(project, kernel, options) {
    const source = structuredClone(project), settings = { ...options };
    return (await runtime()).exportProject(source, kernel, settings, host);
}
