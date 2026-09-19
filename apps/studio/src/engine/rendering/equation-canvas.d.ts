import type { Equation } from './equations';
export interface EquationDrawing {
    /** Serialized UTF-16 source size; Path2D's internal allocation is not measurable. */
    readonly sourceBytes: number;
    readonly glyphCount: number;
    /** Draw in MathJax coordinates; the caller applies equation centering and output scale. */
    paint(context: CanvasRenderingContext2D, progress: number, order: 'together' | 'sequential', color: string): void;
}
export declare const prepareEquationDrawing: (equation: Equation) => EquationDrawing | null;
