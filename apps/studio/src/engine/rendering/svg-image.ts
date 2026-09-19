import { withSvgImage as moonWithSvgImage } from '../../../../../_build/js/release/build/browser_render/browser_render.js';
export function withSvgImage<T>(svg: string, signal: AbortSignal | undefined, draw: (image: HTMLImageElement) => T): Promise<T> {
  return moonWithSvgImage(svg, signal, draw);
}
