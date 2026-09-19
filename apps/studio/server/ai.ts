/** Native SDK bindings and TypeScript declarations; policy and lifecycle live in MoonBit. */
import OpenAI from 'openai';
import { zodTextFormat } from 'openai/helpers/zod';
import * as Y from 'yjs';
import { z } from 'zod';
import type { ReasoningEffort } from 'openai/resources/shared';
import type { ServiceTier } from 'openai/resources/responses/responses';
import type { EditProposal } from '../shared/ai';
import type { AiHistorySchema } from '../shared/ai-conversation';
import * as schemas from '../../../_build/js/release/build/schemas/schemas.js';
import * as moon from '../../../_build/js/release/build/ai_service/ai_service.js';

export const ROOM_PATTERN = /^[a-zA-Z0-9_-]{16,80}$/;
export interface AiRequest {
  roomId: string; sceneId: string; compositionId: string | null; transitionId: string | null;
  selectedIds: string[]; prompt: string; history?: z.infer<typeof AiHistorySchema>; supportsCompositionAppends?: boolean;
}
export const AiRequestSchema = schemas.aiRequestSchema() as z.ZodType<AiRequest>;
export interface ImageGeneration {
  model: string; quality: 'low' | 'medium' | 'high';
  store(bytes: Uint8Array<ArrayBuffer>, mime: string): Promise<string>;
}
export interface ResponseTuning { reasoningEffort?: Exclude<ReasoningEffort, null>; serviceTier?: Exclude<ServiceTier, null> }
export const responseTuningState = { disabled: false };
export const aiRuntime = { OpenAI, zodTextFormat, Y, ZodError: z.ZodError, tuningState: responseTuningState };
export const imageQuality: (value: string | undefined) => ImageGeneration['quality'] = moon.imageQuality as typeof imageQuality;
export const responseTuning: (env: { OPENAI_REASONING_EFFORT?: string; OPENAI_SERVICE_TIER?: string }) => ResponseTuning = moon.responseTuning;
export function createEditProposal(doc: Y.Doc, input: AiRequest, apiKey: string, model: string, options: { images?: ImageGeneration; tuning?: ResponseTuning } = {}): Promise<EditProposal> {
  return moon.createEditProposal(doc, input, apiKey, model, options, aiRuntime);
}
export function aiErrorMessage(error: unknown): string { return moon.aiErrorMessage(error, aiRuntime); }
