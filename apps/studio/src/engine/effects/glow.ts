import { createGlowRenderer as moonCreateGlow } from '../../../../../_build/js/release/build/browser_render/browser_render.js';
export { GLOW_STYLE } from './glow-style';

export interface GlowRenderer {
  readonly canvas: HTMLCanvasElement;
  /** Context loss permanently disables this renderer; the caller uses Canvas 2D afterward. */
  readonly lost: boolean;
  render(source: TexImageSource, width: number, height: number, sigmaPixels: number): void;
  dispose(): void;
}


export const createGlowRenderer: () => GlowRenderer | null = moonCreateGlow;
