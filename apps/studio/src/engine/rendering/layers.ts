import type { RenderObject } from '../evaluate';
import type { ObjectBounds } from '../render-contract';
import type { GlowRenderer } from '../effects/glow';
import { renderResources } from '../renderer';
import { createLayerCache } from '../../../../../_build/js/release/build/browser_render/browser_render.js';

export interface RasterLayer {
  canvas: HTMLCanvasElement;
  sceneBounds: ObjectBounds;
}

/** Compatibility facade for the MoonBit cache and its resource ownership. */
export class LayerCache {
  private readonly core = createLayerCache(renderResources);
  clear(): void { this.core.clear(); }
  retain(ids: Set<string>): void { this.core.retain(ids); }
  get(item: RenderObject, scale: number, glow: GlowRenderer, signal: AbortSignal): Promise<RasterLayer | null> {
    return this.core.get(item, scale, glow, signal);
  }
}
