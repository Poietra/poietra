import { texCompletions, texCompletionContext as context, matchTexCompletions as matches, applyTexCompletion as apply } from '../../../../_build/js/release/build/boundary/boundary.js';

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


export const TEX_COMPLETIONS: TexCompletion[] = texCompletions();
export const texCompletionContext: (text: string, caret: number) => { start: number; query: string } | null = context;
export const matchTexCompletions: (query: string, limit?: number) => TexCompletion[] = matches;
export const applyTexCompletion: (text: string, start: number, caret: number, item: TexCompletion) => { text: string; caret: number } = apply;
