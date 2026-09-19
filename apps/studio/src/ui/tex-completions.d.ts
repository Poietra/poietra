export interface TexCompletion {
    /** Shown in the list, for example \frac{}{}. */
    label: string;
    insert: string;
    /** Caret offset inside insert after accepting. */
    caret: number;
    /** Command names matched against the letters typed after the backslash. */
    keys: string[];
    hint?: string;
}
export declare const TEX_COMPLETIONS: TexCompletion[];
export declare const texCompletionContext: (text: string, caret: number) => {
    start: number;
    query: string;
} | null;
export declare const matchTexCompletions: (query: string, limit?: number) => TexCompletion[];
export declare const applyTexCompletion: (text: string, start: number, caret: number, item: TexCompletion) => {
    text: string;
    caret: number;
};
