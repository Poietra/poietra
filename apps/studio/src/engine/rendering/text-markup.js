import { measureText } from "./fonts.js";
import { textMarkup as moonTextMarkup } from "../../../../../_build/js/release/build/boundary/boundary.js";
export const TEXT_CLIP_VERTICAL_EM = 0.2;
export function textMarkup(item, prefix, glyphOpacity) {
    return moonTextMarkup(item, prefix, glyphOpacity, measureText);
}
