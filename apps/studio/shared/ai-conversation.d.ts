import type { z } from 'zod';
export declare const AI_HISTORY_MAX_ENTRIES = 24;
export declare const AI_HISTORY_MAX_CHARACTERS = 24000;
export declare const AI_HISTORY_MAX_CONTENT = 3000;
export declare const AI_REQUEST_MAX_BYTES: number;
export type AiConversationTurn = {
    role: 'user';
    content: string;
} | {
    role: 'assistant';
    content: string;
    proposalStatus?: 'proposed' | 'applied' | 'discarded';
};
export declare const AiHistorySchema: z.ZodType<AiConversationTurn[]>;
export { trimAiHistory } from '../../../_build/js/release/build/boundary/boundary.js';
