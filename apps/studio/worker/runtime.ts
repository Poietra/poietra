/** Native platform/package wiring; room state and request policy live in MoonBit. */
import * as Y from 'yjs';
import * as sync from 'y-protocols/sync';
import { aiRuntime, createEditProposal, type AiRequest } from '../server/ai';
import type { EditProposal } from '../shared/ai';
import type { AssetKind, AssetMetadata, AssetResult } from './room-assets';
import * as rooms from '../../../_build/js/release/build/worker_room/worker_room.js';
import * as server from '../../../_build/js/release/build/worker_server/worker_server.js';
export { AuthRecord, UserAccount } from './accounts';

const runtime = { Y, sync, ai: aiRuntime, createEditProposal };
export default {
  fetch(request: Request, env: Env): Promise<Response> { return server.handleRequest(request, env, aiRuntime); },
} satisfies ExportedHandler<Env>;

export interface ProjectRoom {
  fetch(request: Request): Promise<Response>;
  webSocketMessage(socket: WebSocket, message: ArrayBuffer | string): void;
  webSocketClose(socket: WebSocket): void;
  webSocketError(socket: WebSocket): void;
  getAssetMetadata(kind: AssetKind, id: string): AssetMetadata | null;
  beginAssetUpload(room: string, kind: AssetKind): Promise<AssetResult<string>>;
  finishAssetUpload(key: string, digest: string, mime: string, size: number): AssetResult<string>;
  discardAssetUpload(key: string): Promise<void>;
  alarm(): Promise<void>;
  saveImage(room: string, bytes: Uint8Array<ArrayBuffer>, mime: string): Promise<string>;
  propose(input: AiRequest): Promise<{ status: number; body: EditProposal | { error: string } }>;
}
export const ProjectRoom: { new(ctx: DurableObjectState, env: Env): ProjectRoom } = rooms.projectRoomClass(runtime);
