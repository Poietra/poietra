import * as promises from 'node:fs/promises';
import { Readable } from 'node:stream';
export function fileSystemPromises() { return promises; }
export function webRequestBody(request) { return Readable.toWeb(request); }
