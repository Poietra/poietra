interface UploadedAsset {
    size: number;
    mime: string;
    digest: string;
}
export declare const uploadMediaToR2: (bucket: R2Bucket, key: string, request: Request) => Promise<UploadedAsset>;
export declare const uploadImageRequestToR2: (bucket: R2Bucket, key: string, request: Request) => Promise<UploadedAsset>;
export declare const uploadImageToR2: (bucket: R2Bucket, key: string, bytes: Uint8Array<ArrayBuffer>, mime: string) => Promise<UploadedAsset>;
export {};
