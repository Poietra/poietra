import * as moonbit from "../../../../_build/js/release/build/boundary/boundary.js";
import { getEquation, prepareEquations } from "./rendering/equations.js";
import { embeddedFontStyles, measureText, prepareFonts } from "./rendering/fonts.js";
import { prepareImages, preparedImage } from "./rendering/images.js";
export { prepareVideoFrame as prepareFrame } from "./rendering/videos.js";
export const renderResources = { getEquation, prepareEquations, embeddedFontStyles, measureText, prepareFonts, prepareImages, preparedImage };
export function prepareScene(scene) { return moonbit.prepareRenderScene(scene, renderResources); }
export function objectBounds(item) { return moonbit.objectBounds(item, renderResources); }
export function frameToSvg(frame, options = {}) { return moonbit.frameToSvg(frame, options, renderResources); }
export function frameToSvgView(frame, options = {}) { return moonbit.frameToSvgView(frame, options, renderResources); }
