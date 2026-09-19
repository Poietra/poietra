import * as moonbit from '../../../../../_build/js/release/build/browser_render/browser_render.js';
export const FONT_FAMILY = "'Poietra Inter', 'Poietra Noto Sans JP', sans-serif";
export interface TextMetrics { width: number; height: number; lineHeight: number; baseline: number }
const loadCatalog = () => import('./font-assets').then(module => module.fontAssets);
export function prepareFonts(sources: string[]): Promise<void> { return moonbit.prepareFonts(sources, loadCatalog); }
export const embeddedFontStyles: (sources: string[]) => string = moonbit.embeddedFontStyles;
export const measureText: (text: string, size: number) => TextMetrics = moonbit.measureText;
