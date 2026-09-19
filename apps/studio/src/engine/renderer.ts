import type { Scene } from '../../shared/model';
import type { Frame, RenderObject } from './evaluate';
import type { ObjectBounds, SvgOptions } from './render-contract';
import * as moonbit from '../../../../_build/js/release/build/boundary/boundary.js';
import { getEquation, prepareEquations } from './rendering/equations';
import { embeddedFontStyles, measureText, prepareFonts } from './rendering/fonts';
import { prepareImages, preparedImage } from './rendering/images';
export { prepareVideoFrame as prepareFrame } from './rendering/videos';

const resources = { getEquation, prepareEquations, embeddedFontStyles, measureText, prepareFonts, prepareImages, preparedImage };
export function prepareScene(scene: Scene): Promise<void> { return moonbit.prepareRenderScene(scene, resources); }
export function objectBounds(item: RenderObject): ObjectBounds { return moonbit.objectBounds(item, resources); }
export function frameToSvg(frame: Frame, options: SvgOptions = {}): string { return moonbit.frameToSvg(frame, options, resources); }
