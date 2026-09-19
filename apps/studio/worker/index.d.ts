import { DurableObject } from 'cloudflare:workers';
import type { AccountProject, AuthProvider } from '../shared/accounts';
import type { AuthRecordValue } from '../server/auth';
import type { AiRequest } from '../server/ai';
import type { AssetKind } from './room-assets';
declare const _default: {
    fetch(request: Request, env: Env): Promise<Response>;
};
export default _default;
export declare class ProjectRoom extends DurableObject<Env> {
    #private;
    constructor(ctx: DurableObjectState, env: Env);
    fetch(request: Request): Promise<Response>;
    webSocketMessage(socket: WebSocket, message: ArrayBuffer | string): Promise<void>;
    webSocketClose(socket: WebSocket): Promise<void>;
    webSocketError(socket: WebSocket): Promise<void>;
    getAssetMetadata(kind: AssetKind, id: string): Promise<import("./room-assets").AssetMetadata | null>;
    beginAssetUpload(room: string, kind: AssetKind): Promise<import("./room-assets").AssetResult<string>>;
    finishAssetUpload(key: string, digest: string, mime: string, size: number): Promise<import("./room-assets").AssetResult<string>>;
    discardAssetUpload(key: string): Promise<void>;
    alarm(): Promise<void>;
    saveImage(room: string, bytes: Uint8Array<ArrayBuffer>, mime: string): Promise<string>;
    propose(input: AiRequest): Promise<{
        status: number;
        body: import("../shared/ai").EditProposal | {
            error: string;
        };
    }>;
}
export declare class AuthRecord extends DurableObject<Env> {
    #private;
    constructor(ctx: DurableObjectState, env: Env);
    put(value: AuthRecordValue): Promise<void>;
    getSession(now: number): Promise<import("../server/auth").StoredSession | null>;
    takeFlow(provider: AuthProvider, browserHash: string, origin: string, now: number): Promise<import("../server/auth").AuthFlow | null>;
    erase(): Promise<void>;
    alarm(): Promise<void>;
}
export declare class UserAccount extends DurableObject<Env> {
    #private;
    constructor(ctx: DurableObjectState, env: Env);
    listProjects(): Promise<AccountProject[]>;
    putProject(project: AccountProject): Promise<boolean>;
    deleteProject(room: string): Promise<void>;
}
