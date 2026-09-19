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
export async function imageDigest(bytes: Uint8Array<ArrayBuffer>): Promise<string> {
  return [...new Uint8Array(await crypto.subtle.digest('SHA-256', bytes))].map(value => value.toString(16).padStart(2, '0')).join('');
}
export async function readImageBody(request: Request): Promise<Uint8Array<ArrayBuffer>> {
  const reader = request.body?.getReader();
  if (!reader) throw new Error('画像がありません。');
  const chunks: Uint8Array[] = []; let size = 0;
  try {
    while (true) {
      const { value, done } = await reader.read(); if (done) break;
      size += value.byteLength;
      if (size > IMAGE_BYTES_LIMIT) { await reader.cancel(); throw new Error('画像データは 1 MB 以下にしてください。'); }
      chunks.push(value);
    }
  } finally { reader.releaseLock(); }
  const bytes = new Uint8Array(size); let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
  if (!imageMime(bytes)) throw new Error('PNG・JPEG・WebP の画像を選択してください。');
  return bytes;
}
export const imageHeaders = (mime: string) => ({ 'Content-Type': mime, 'Cache-Control': 'private, max-age=31536000, immutable', 'X-Content-Type-Options': 'nosniff', 'Content-Security-Policy': "default-src 'none'", 'Cross-Origin-Resource-Policy': 'same-origin' });
