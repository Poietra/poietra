import * as http from '../../../_build/js/release/build/http_runtime/http_runtime.js';
import * as moon from '../../../_build/js/release/build/boundary/boundary.js';
import type { z } from 'zod';
import * as schemas from '../../../_build/js/release/build/schemas/schemas.js';

export const MEDIA_FILE_LIMIT = 32 * 1024 * 1024;
export const MEDIA_ROOM_BYTES_LIMIT = 128 * 1024 * 1024;
export const MEDIA_CHUNK_BYTES = 128 * 1024;
export const MEDIA_MIMES = ['video/mp4', 'video/webm', 'audio/mpeg', 'audio/wav', 'audio/ogg', 'audio/flac', 'audio/mp4', 'audio/webm'] as const;
export const MEDIA_ACCEPT = MEDIA_MIMES.join(',') + ',audio/x-wav,audio/x-flac,audio/x-m4a,.mp3,.wav,.ogg,.flac,.m4a,.mp4,.webm';
export const MEDIA_ASSET_PATH = /^\/api\/rooms\/([a-zA-Z0-9_-]{16,80})\/media\/([a-f0-9]{64})$/;
export const MEDIA_UPLOAD_PATH = /^\/api\/rooms\/([a-zA-Z0-9_-]{16,80})\/media$/;
export const MEDIA_DATA_URL = /^data:(video\/(?:mp4|webm)|audio\/(?:mpeg|wav|ogg|flac|mp4|webm));base64,[A-Za-z0-9+/]+={0,2}$/;
export interface MediaAsset { src: string; mime: string; duration: number; width?: number; height?: number; hasAudio: boolean; waveform?: number[] }
export interface MediaPlayback { start: number; offset: number; duration: number }
export interface AudioTrack extends MediaPlayback { id: string; name: string; asset: MediaAsset; volume: number; muted: boolean }
export const MediaAssetSchema = schemas.mediaAssetSchema() as z.ZodType<MediaAsset>;
export const MediaPlaybackSchema = schemas.mediaPlaybackSchema() as z.ZodType<MediaPlayback>;
export const AudioTrackSchema = schemas.audioTrackSchema() as z.ZodType<AudioTrack>;

export const canonicalMediaMime: (mime: string) => string = moon.canonicalMediaMime;
export const mediaMime: (bytes: Uint8Array, declared?: string) => string | null = moon.mediaMime;

export type ByteRange = { start: number; end: number };
export const mediaByteRange: (header: string, size: number) => ByteRange | null = http.mediaByteRange;
export const mediaHeaders: (mime: string, digest: string) => Record<string, string> = http.mediaHeaders;
export interface MediaUploadError extends Error { readonly status: number }
export const MediaUploadError: { new(message: string, status?: number): MediaUploadError } = http.mediaErrorType();
/** The sink must consume each chunk before resolving; the buffer is then reused. */
export const writeMediaChunks: (input: AsyncIterable<Uint8Array>, declared: string, contentLength: string | null, write: (chunk: Uint8Array, part: number) => void | Promise<void>) => Promise<{ size: number; mime: string }> = http.writeMediaChunks;
export const mediaResponsePlan: (request: { range: string | null; ifRange: string | null; ifNoneMatch: string | null }, metadata: { size: number; mime: string }, digest: string) => { status: number; headers: Record<string, string>; range?: ByteRange } = http.mediaResponsePlan;
