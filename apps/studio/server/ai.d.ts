/** Native SDK bindings and TypeScript declarations; policy and lifecycle live in MoonBit. */
import OpenAI from 'openai';
import { zodTextFormat } from 'openai/helpers/zod';
import * as Y from 'yjs';
import { z } from 'zod';
import type { ReasoningEffort } from 'openai/resources/shared';
import type { ServiceTier } from 'openai/resources/responses/responses';
import type { EditProposal } from '../shared/ai';
import type { AiHistorySchema } from '../shared/ai-conversation';
export declare const ROOM_PATTERN: RegExp;
export interface AiRequest {
    roomId: string;
    sceneId: string;
    compositionId: string | null;
    transitionId: string | null;
    selectedIds: string[];
    prompt: string;
    history?: z.infer<typeof AiHistorySchema>;
    supportsCompositionAppends?: boolean;
}
export declare const AiRequestSchema: z.ZodType<AiRequest>;
export interface ImageGeneration {
    model: string;
    quality: 'low' | 'medium' | 'high';
    store(bytes: Uint8Array<ArrayBuffer>, mime: string): Promise<string>;
}
export interface ResponseTuning {
    reasoningEffort?: Exclude<ReasoningEffort, null>;
    serviceTier?: Exclude<ServiceTier, null>;
}
export declare const responseTuningState: {
    disabled: boolean;
};
export declare const aiRuntime: {
    OpenAI: typeof OpenAI;
    zodTextFormat: typeof zodTextFormat;
    Y: typeof Y;
    ZodError: z.core.$constructor<z.ZodError<unknown>, z.core.$ZodIssue[]>;
    tuningState: {
        disabled: boolean;
    };
};
export declare const imageQuality: (value: string | undefined) => ImageGeneration['quality'];
export declare const responseTuning: (env: {
    OPENAI_REASONING_EFFORT?: string;
    OPENAI_SERVICE_TIER?: string;
}) => ResponseTuning;
export declare function createEditProposal(doc: Y.Doc, input: AiRequest, apiKey: string, model: string, options?: {
    images?: ImageGeneration;
    tuning?: ResponseTuning;
}): Promise<EditProposal>;
export declare function aiErrorMessage(error: unknown): string;
