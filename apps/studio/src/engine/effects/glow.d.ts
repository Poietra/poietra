export { GLOW_STYLE } from './glow-style';
export interface GlowRenderer {
    readonly canvas: HTMLCanvasElement;
    /** Context loss permanently disables this renderer; the caller uses Canvas 2D afterward. */
    readonly lost: boolean;
    render(source: TexImageSource, width: number, height: number, sigmaPixels: number): void;
    dispose(): void;
}
export declare const createGlowRenderer: () => GlowRenderer | null;
