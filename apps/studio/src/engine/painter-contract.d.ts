import type { Frame } from './evaluate';
export type PaintBackend = 'webgl2' | 'canvas2d';
export interface PaintOptions {
    signal?: AbortSignal;
}
/** A completed frame borrowed until the next render, disposal or cancellation. */
export interface PaintDraft {
    /**
     * Copy once to an already-sized destination, preserving its drawing state.
     * Returns false without drawing if already presented, expired or canceled.
     * The backing canvas is never exposed; callers must present synchronously
     * before starting another render or renderDraft on this painter.
     */
    present(context: CanvasRenderingContext2D): boolean;
}
/** Browser drawing shared by preview and export; independent of React and editing state. */
export interface FramePainter {
    /** The active backend, including a change to Canvas 2D after WebGL context loss. */
    readonly backend: PaintBackend;
    /**
     * Render a complete frame, including background and object effects, to the target canvas.
     * prepareScene(scene) must have completed first. Do not mutate the supplied frame.
     * Use the current canvas.width/height; preserve the Scene aspect ratio and letterbox
     * with frame.background. Callers serialize renders and resize only between renders.
     * The promise resolves when pixels can be captured by WebCodecs. Export must not skip
     * frames; preview may coalesce pending frames before calling this method.
     * Cancellation rejects with AbortError.
     */
    render(frame: Frame, options?: PaintOptions): Promise<void>;
    /**
     * Optional atomic preview path. Render at positive integer pixel dimensions
     * without touching the constructor's target canvas. The caller checks that
     * this frame is still wanted, then presents it directly to the display.
     * Shares render's preparation, serialization and cancellation contract.
     */
    renderDraft?(frame: Frame, width: number, height: number, options?: PaintOptions): Promise<PaintDraft>;
    /** Idempotent. Release GPU and image resources; an in-flight render must stop safely. */
    dispose(): void;
}
/** Implement createFramePainter in moonbit/browser_render. The caller owns the canvas. */
export interface PainterContract {
    createFramePainter(canvas: HTMLCanvasElement): Promise<FramePainter>;
}
