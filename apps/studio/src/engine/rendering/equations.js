import * as moonbit from "../../../../../_build/js/release/build/boundary/boundary.js";
import * as resources from "../../../../../_build/js/release/build/browser_render/browser_render.js";
import { loadMathRuntime } from "../../platform/render-host.mjs";
export const EQUATION_UNITS_PER_EM = 1000;
export const EQUATION_WRITE_STROKE_UNITS = 18;
export function prepareEquations(sources) { return resources.prepareEquations(sources, loadMathRuntime); }
export const getEquation = resources.getEquation;
export const equationGlyphProgress = moonbit.equationGlyphProgress;
export const equationFillProgress = moonbit.equationFillProgress;
export const equationMarkup = moonbit.equationMarkup;
