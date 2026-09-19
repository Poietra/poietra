import type { RenderObject } from '../evaluate';
import * as moonbit from '../../../../../_build/js/release/build/browser_render/browser_render.js';

export interface TextDrawing {
  readonly key: string;
  readonly bytes: number;
  paint(context: CanvasRenderingContext2D, item: RenderObject): void;
  dispose(): void;
}

export const textDrawingKey: (item: RenderObject, scale: number) => string | null = moonbit.textDrawingKey;
export const prepareTextDrawing: (item: RenderObject, scale: number, maxBytes: number, signal: AbortSignal) => Promise<TextDrawing | null> = moonbit.prepareTextDrawing;
