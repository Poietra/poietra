import { renderResources } from "./renderer.js";
import { createFramePainter as moonCreatePainter } from "../../../../_build/js/release/build/browser_render/browser_render.js";
export function createFramePainter(canvas) {
    return moonCreatePainter(canvas, renderResources);
}
