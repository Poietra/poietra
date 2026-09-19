import type { ComponentType } from 'react';
import type { Scene } from '../../shared/model';
import type { Frame } from '../engine/evaluate';
import type { PainterContract } from '../engine/painter-contract';
import type { RendererContract } from '../engine/render-contract';
import { CanvasFrame as MoonCanvasFrame } from '../../../../_build/js/release/build/ui/ui.js';

export interface CanvasPresentation {
  frame: Frame;
  key: string;
  width: number;
  height: number;
}

interface Props {
  frame: Frame;
  scene: Scene;
  renderer: RendererContract;
  createFramePainter: PainterContract['createFramePainter'];
  presentationKey: string;
  width: number;
  height: number;
  visible: boolean;
  onPresent: (presentation: CanvasPresentation | null) => void;
}

export const CanvasFrame: ComponentType<Props> = MoonCanvasFrame;
