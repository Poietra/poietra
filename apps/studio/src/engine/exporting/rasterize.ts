import { drawSvgFrame as moonDrawSvgFrame } from '../../../../../_build/js/release/build/browser_render/browser_render.js';

export const drawSvgFrame: (
  svg: string, context: CanvasRenderingContext2D, width: number, height: number,
  sceneWidth: number, sceneHeight: number, background: string, signal?: AbortSignal,
) => Promise<void> = moonDrawSvgFrame;
