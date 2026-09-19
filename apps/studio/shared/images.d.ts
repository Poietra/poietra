import type { ImageAsset } from "./scene-types";
export type { ImageAsset } from "./scene-types";
import type { z } from 'zod';
export declare const IMAGE_BYTES_LIMIT: number;
export declare const IMAGE_ROOM_BYTES_LIMIT: number;
export declare const IMAGE_EDGE_LIMIT = 2048;
export declare const IMAGE_ASSET_PATH: RegExp;
export declare const IMAGE_UPLOAD_PATH: RegExp;
export declare const IMAGE_DATA_URL: RegExp;
export declare const imageSource: z.ZodType<string>;
export declare const ImageAssetSchema: z.ZodType<ImageAsset>;
/** Uploaded assets are immutable, raster-only, and content addressed. */
export declare const imageMime: (bytes: Uint8Array) => string | null;
export declare const imageDigest: (bytes: Uint8Array<ArrayBuffer>) => Promise<string>;
export declare const readImageBody: (request: Request) => Promise<Uint8Array<ArrayBuffer>>;
export declare const imageHeaders: (mime: string) => Record<string, string>;
