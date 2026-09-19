import type { RenderObject } from '../evaluate';
import type { ObjectBounds } from '../render-contract';
import type { GlowRenderer } from '../effects/glow';
export interface RasterLayer {
    canvas: HTMLCanvasElement;
    sceneBounds: ObjectBounds;
}
/** Compatibility facade for the MoonBit cache and its resource ownership. */
export declare class LayerCache {
    private readonly core;
    clear(): void;
    retain(ids: Set<string>): void;
    get(item: RenderObject, scale: number, glow: GlowRenderer, signal: AbortSignal): Promise<RasterLayer | null>;
}
