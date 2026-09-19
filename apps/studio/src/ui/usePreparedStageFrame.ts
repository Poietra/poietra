import type { Frame } from '../engine/evaluate';
import type { RendererContract } from '../engine/render-contract';
import { usePreparedStageFrame as moonUsePreparedStageFrame } from '../../../../_build/js/release/build/ui/ui.js';
export const usePreparedStageFrame: (source: Frame, renderer: RendererContract, scope: string) => {
  frame: Frame; ready: boolean; pending: boolean; error: boolean;
} = moonUsePreparedStageFrame;
