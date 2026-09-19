/** Native SDK bindings and TypeScript declarations; policy and lifecycle live in MoonBit. */
import OpenAI from "openai";
import { zodTextFormat } from "openai/helpers/zod";
import * as Y from "yjs";
import { z } from "zod";
import * as schemas from "../../../_build/js/release/build/schemas/schemas.js";
import * as moon from "../../../_build/js/release/build/ai_service/ai_service.js";
export const ROOM_PATTERN = /^[a-zA-Z0-9_-]{16,80}$/;
export const AiRequestSchema = schemas.aiRequestSchema();
export const responseTuningState = { disabled: false };
export const aiRuntime = { OpenAI, zodTextFormat, Y, ZodError: z.ZodError, tuningState: responseTuningState };
export const imageQuality = moon.imageQuality;
export const responseTuning = moon.responseTuning;
export function createEditProposal(doc, input, apiKey, model, options = {}) {
    return moon.createEditProposal(doc, input, apiKey, model, options, aiRuntime);
}
export function aiErrorMessage(error) { return moon.aiErrorMessage(error, aiRuntime); }
