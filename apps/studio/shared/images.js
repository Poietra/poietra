import * as http from "../../../_build/js/release/build/http_runtime/http_runtime.js";
import * as moon from "../../../_build/js/release/build/boundary/boundary.js";
import * as schemas from "../../../_build/js/release/build/schemas/schemas.js";
export const IMAGE_BYTES_LIMIT = 1024 * 1024;
export const IMAGE_ROOM_BYTES_LIMIT = 64 * 1024 * 1024;
export const IMAGE_EDGE_LIMIT = 2048;
export const IMAGE_ASSET_PATH = /^\/api\/rooms\/([a-zA-Z0-9_-]{16,80})\/images\/([a-f0-9]{64})$/;
export const IMAGE_UPLOAD_PATH = /^\/api\/rooms\/([a-zA-Z0-9_-]{16,80})\/images$/;
export const IMAGE_DATA_URL = /^data:image\/(png|jpeg|webp);base64,[A-Za-z0-9+/]+={0,2}$/;
export const imageSource = schemas.imageSourceSchema();
export const ImageAssetSchema = schemas.imageAssetSchema();
/** Uploaded assets are immutable, raster-only, and content addressed. */
export const imageMime = moon.imageMime;
export const imageDigest = http.imageDigest;
export const readImageBody = http.readImageBody;
export const imageHeaders = http.imageHeaders;
