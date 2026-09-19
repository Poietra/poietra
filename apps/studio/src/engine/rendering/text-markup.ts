import type { RenderObject } from '../evaluate';
import { measureText } from './fonts';
import { textMarkup as moonTextMarkup } from '../../../../../_build/js/release/build/boundary/boundary.js';
export const TEXT_CLIP_VERTICAL_EM = 0.2;
export function textMarkup(item: RenderObject, prefix: string, glyphOpacity?: (index: number) => number): string {
  return moonTextMarkup(item, prefix, glyphOpacity, measureText);
}
