import * as moon from '../../../_build/js/release/build/room_assets/room_assets.js';

export type AssetKind = 'images' | 'media';
export interface AssetMetadata { mime: string; size: number; objectKey: string | null }
export type AssetResult<T> = { ok: true; value: T } | { ok: false; error: string; status: number };
export interface RoomAssets {
  get(kind: AssetKind, id: string): AssetMetadata | null;
  begin(room: string, kind: AssetKind): Promise<AssetResult<string>>;
  finish(key: string, digest: string, mime: string, size: number): AssetResult<string>;
  discard(key: string): Promise<void>;
  alarm(): Promise<void>;
}
export const RoomAssets: { new(ctx: DurableObjectState, bucket: R2Bucket): RoomAssets } = moon.roomAssetsClass();
