import interUrl from "@fontsource/inter/files/inter-latin-400-normal.woff2?url";
import japaneseCss from "@fontsource/noto-sans-jp/400.css?raw";
// Unicode ranges select only the locally bundled subsets a scene actually uses.
const japaneseAssets = import.meta.glob('../../../node_modules/@fontsource/noto-sans-jp/files/noto-sans-jp-{[0-9]*,latin,latin-ext,cyrillic,vietnamese}-400-normal.woff2', { eager: true, query: '?url', import: 'default' });
import { createFontCatalog } from "../../../../../_build/js/release/build/browser_render/browser_render.js";
export const fontAssets = createFontCatalog(interUrl, japaneseCss, japaneseAssets);
