import { renderResources } from "../renderer.js";
import { createLayerCache } from "../../../../../_build/js/release/build/browser_render/browser_render.js";
/** Compatibility facade for the MoonBit cache and its resource ownership. */
export class LayerCache {
    core = createLayerCache(renderResources);
    clear() { this.core.clear(); }
    retain(ids) { this.core.retain(ids); }
    get(item, scale, glow, signal) {
        return this.core.get(item, scale, glow, signal);
    }
}
