import type { AssetKind, AssetMetadata, AssetResult } from './room-assets';
export declare const assetValue: <T>(result: AssetResult<T>) => T;
export declare const r2AssetResponse: (request: Request, bucket: R2Bucket, kind: AssetKind, digest: string, metadata: AssetMetadata) => Promise<Response | null>;
export declare const handleAssetRequest: (request: Request, env: Env) => Promise<Response | null>;
