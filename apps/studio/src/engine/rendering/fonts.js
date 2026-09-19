import * as moonbit from "../../../../../_build/js/release/build/browser_render/browser_render.js";
export const FONT_FAMILY = "'Poietra Inter', 'Poietra Noto Sans JP', sans-serif";
const loadCatalog = () => import("./font-assets.js").then(module => module.fontAssets);
export function prepareFonts(sources) { return moonbit.prepareFonts(sources, loadCatalog); }
export const embeddedFontStyles = moonbit.embeddedFontStyles;
export const measureText = moonbit.measureText;
