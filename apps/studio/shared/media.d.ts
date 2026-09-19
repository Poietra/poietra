import type { MediaAsset, MediaPlayback, AudioTrack } from "./scene-types";
export type { MediaAsset, MediaPlayback, AudioTrack } from "./scene-types";
import type { z } from 'zod';
export declare const MEDIA_FILE_LIMIT: number;
export declare const MEDIA_ROOM_BYTES_LIMIT: number;
export declare const MEDIA_CHUNK_BYTES: number;
export declare const MEDIA_MIMES: readonly ['video/mp4', 'video/webm', 'audio/mpeg', 'audio/wav', 'audio/ogg', 'audio/flac', 'audio/mp4', 'audio/webm'];
export declare const MEDIA_ACCEPT: string;
export declare const MEDIA_ASSET_PATH: RegExp;
export declare const MEDIA_UPLOAD_PATH: RegExp;
export declare const MEDIA_DATA_URL: RegExp;
export declare const MediaAssetSchema: z.ZodType<MediaAsset>;
export declare const MediaPlaybackSchema: z.ZodType<MediaPlayback>;
export declare const AudioTrackSchema: z.ZodType<AudioTrack>;
export declare const canonicalMediaMime: (mime: string) => string;
export declare const mediaMime: (bytes: Uint8Array, declared?: string) => string | null;
export type ByteRange = {
    start: number;
    end: number;
};
export declare const mediaByteRange: (header: string, size: number) => ByteRange | null;
export declare const mediaHeaders: (mime: string, digest: string) => Record<string, string>;
export interface MediaUploadError extends Error {
    readonly status: number;
}
export declare const MediaUploadError: {
    new (message: string, status?: number): MediaUploadError;
};
/** The sink must consume each chunk before resolving; the buffer is then reused. */
export declare const writeMediaChunks: (input: AsyncIterable<Uint8Array>, declared: string, contentLength: string | null, write: (chunk: Uint8Array, part: number) => void | Promise<void>) => Promise<{
    size: number;
    mime: string;
}>;
export declare const mediaResponsePlan: (request: {
    range: string | null;
    ifRange: string | null;
    ifNoneMatch: string | null;
}, metadata: {
    size: number;
    mime: string;
}, digest: string) => {
    status: number;
    headers: Record<string, string>;
    range?: ByteRange;
};
