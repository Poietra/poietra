export declare const FONT_FAMILY = "'Poietra Inter', 'Poietra Noto Sans JP', sans-serif";
export interface TextMetrics {
    width: number;
    height: number;
    lineHeight: number;
    baseline: number;
}
export declare function prepareFonts(sources: string[]): Promise<void>;
export declare const embeddedFontStyles: (sources: string[]) => string;
export declare const measureText: (text: string, size: number) => TextMetrics;
