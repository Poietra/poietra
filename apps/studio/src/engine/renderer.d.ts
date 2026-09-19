import type { Scene } from '../../shared/model';
import type { Frame, RenderObject } from './evaluate';
import type { ObjectBounds, SvgOptions } from './render-contract';
import { prepareEquations } from './rendering/equations';
import { prepareFonts } from './rendering/fonts';
export { prepareVideoFrame as prepareFrame } from './rendering/videos';
export declare const renderResources: {
    getEquation: (source: string) => import("./rendering/equations").Equation | null;
    prepareEquations: typeof prepareEquations;
    embeddedFontStyles: (sources: string[]) => string;
    measureText: (text: string, size: number) => import("./rendering/fonts").TextMetrics;
    prepareFonts: typeof prepareFonts;
    prepareImages: (scene: Scene) => Promise<void>;
    preparedImage: (src: string | undefined) => string | null;
};
export declare function prepareScene(scene: Scene): Promise<void>;
export declare function objectBounds(item: RenderObject): ObjectBounds;
export declare function frameToSvg(frame: Frame, options?: SvgOptions): string;
