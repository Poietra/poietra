import type { FramePainter } from './painter-contract';
import { VideoFrames } from './rendering/videos';
import { renderResources } from './renderer';
import { createFramePainter as moonCreatePainter } from '../../../../_build/js/release/build/browser_render/browser_render.js';

const services = { createVideoFrames: () => new VideoFrames() };
export function createFramePainter(canvas: HTMLCanvasElement): Promise<FramePainter> {
  return moonCreatePainter(canvas, renderResources, services);
}
