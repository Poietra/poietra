export declare const EQUATION_UNITS_PER_EM = 1000;
export declare const EQUATION_WRITE_STROKE_UNITS = 18;
interface MathNode {
    tag: string;
    attributes: Record<string, string>;
    children: MathNode[];
}
export interface Equation {
    width: number;
    height: number;
    x: number;
    y: number;
    tree: MathNode;
    glyphs: number;
}
export declare function prepareEquations(sources: string[]): Promise<void>;
export declare const getEquation: (source: string) => Equation | null;
export declare const equationGlyphProgress: (progress: number, order: 'together' | 'sequential', glyphs: number, index: number) => number;
export declare const equationFillProgress: (progress: number) => number;
export declare const equationMarkup: (equation: Equation, progress: number, order: 'together' | 'sequential') => string;
export {};
