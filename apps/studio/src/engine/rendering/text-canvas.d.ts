import type { RenderObject } from '../evaluate';
export interface TextDrawing {
    readonly key: string;
    readonly bytes: number;
    paint(context: CanvasRenderingContext2D, item: RenderObject): void;
    dispose(): void;
}
export declare const textDrawingKey: (item: RenderObject, scale: number) => string | null;
export declare const prepareTextDrawing: (item: RenderObject, scale: number, maxBytes: number, signal: AbortSignal) => Promise<TextDrawing | null>;
