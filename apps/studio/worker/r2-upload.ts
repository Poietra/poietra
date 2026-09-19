import * as moon from '../../../_build/js/release/build/r2_upload/r2_upload.js';

interface UploadedAsset { size: number; mime: string; digest: string }
export const uploadMediaToR2: (bucket: R2Bucket, key: string, request: Request) => Promise<UploadedAsset> = moon.uploadMediaToR2;
export const uploadImageRequestToR2: (bucket: R2Bucket, key: string, request: Request) => Promise<UploadedAsset> = moon.uploadImageRequestToR2;
export const uploadImageToR2: (bucket: R2Bucket, key: string, bytes: Uint8Array<ArrayBuffer>, mime: string) => Promise<UploadedAsset> = moon.uploadImageToR2;
