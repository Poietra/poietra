import * as http from '../../../_build/js/release/build/http_runtime/http_runtime.js';
import * as moon from '../../../_build/js/release/build/boundary/boundary.js';
import type { z } from 'zod';
import * as schemas from '../../../_build/js/release/build/schemas/schemas.js';

export const IMAGE_BYTES_LIMIT = 1024 * 1024;
export const IMAGE_ROOM_BYTES_LIMIT = 64 * 1024 * 1024;
export const IMAGE_EDGE_LIMIT = 2048;
export const IMAGE_ASSET_PATH = /^\/api\/rooms\/([a-zA-Z0-9_-]{16,80})\/images\/([a-f0-9]{64})$/;
export const IMAGE_UPLOAD_PATH = /^\/api\/rooms\/([a-zA-Z0-9_-]{16,80})\/images$/;
export const IMAGE_DATA_URL = /^data:image\/(png|jpeg|webp);base64,[A-Za-z0-9+/]+={0,2}$/;
export interface ImageAsset { src: string; width: number; height: number }
export const imageSource = schemas.imageSourceSchema() as z.ZodType<string>;
export const ImageAssetSchema = schemas.imageAssetSchema() as z.ZodType<ImageAsset>;

/** Uploaded assets are immutable, raster-only, and content addressed. */
export const imageMime: (bytes: Uint8Array) => string | null = moon.imageMime;
export const imageDigest: (bytes: Uint8Array<ArrayBuffer>) => Promise<string> = http.imageDigest;
export const readImageBody: (request: Request) => Promise<Uint8Array<ArrayBuffer>> = http.readImageBody;
export const imageHeaders: (mime: string) => Record<string, string> = http.imageHeaders;
