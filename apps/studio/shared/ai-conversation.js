import { aiHistorySchema } from "../../../_build/js/release/build/schemas/schemas.js";
export const AI_HISTORY_MAX_ENTRIES = 24;
export const AI_HISTORY_MAX_CHARACTERS = 24000;
export const AI_HISTORY_MAX_CONTENT = 3000;
// The old 64 KiB transport limit rejected valid Japanese history (24,000 chars
// can occupy 72,000 UTF-8 bytes). Allow bounded JSON escaping of all history,
// prompt and selection fields as well: their schema maxima fit within 256 KiB.
export const AI_REQUEST_MAX_BYTES = 256 * 1024;
export const AiHistorySchema = aiHistorySchema();
export { trimAiHistory } from "../../../_build/js/release/build/boundary/boundary.js";
