import type { FramePainter } from './painter-contract';
import { renderResources } from './renderer';
import { createFramePainter as moonCreatePainter } from '../../../../_build/js/release/build/browser_render/browser_render.js';

export function createFramePainter(canvas: HTMLCanvasElement): Promise<FramePainter> {
  return moonCreatePainter(canvas, renderResources);
}
