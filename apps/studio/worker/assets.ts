import * as moon from '../../../_build/js/release/build/worker_assets/worker_assets.js';
import type { AssetKind, AssetMetadata, AssetResult } from './room-assets';

export const assetValue: <T>(result: AssetResult<T>) => T = moon.assetValue;
export const r2AssetResponse: (request: Request, bucket: R2Bucket, kind: AssetKind, digest: string, metadata: AssetMetadata) => Promise<Response | null> = moon.r2AssetResponse;
export const handleAssetRequest: (request: Request, env: Env) => Promise<Response | null> = moon.handleAssetRequest;
