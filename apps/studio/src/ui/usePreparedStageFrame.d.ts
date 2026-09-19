import type { Frame } from '../engine/evaluate';
import type { RendererContract } from '../engine/render-contract';
export declare const usePreparedStageFrame: (source: Frame, renderer: RendererContract, scope: string) => {
    frame: Frame;
    ready: boolean;
    pending: boolean;
    error: boolean;
};
