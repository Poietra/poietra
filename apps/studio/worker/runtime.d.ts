import { type AiRequest } from '../server/ai';
import type { EditProposal } from '../shared/ai';
import type { AssetKind, AssetMetadata, AssetResult } from './room-assets';
export { AuthRecord, UserAccount } from './accounts';
declare const _default: {
    fetch(request: Request, env: Env): Promise<Response>;
};
export default _default;
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
    propose(input: AiRequest): Promise<{
        status: number;
        body: EditProposal | {
            error: string;
        };
    }>;
}
export declare const ProjectRoom: {
    new (ctx: DurableObjectState, env: Env): ProjectRoom;
};
