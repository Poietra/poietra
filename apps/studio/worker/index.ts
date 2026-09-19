import { DurableObject } from 'cloudflare:workers';
import type { AccountProject, AuthProvider } from '../shared/accounts';
import type { AuthRecordValue } from '../server/auth';
import type { AiRequest } from '../server/ai';
import type { AssetKind } from './room-assets';

// Wrangler bundles this import into a deferred initializer. MoonBit's per-module
// hash seed needs a request/DO context; workerd disallows global random I/O.
const runtime = () => import('./runtime');
export default {
  async fetch(request: Request, env: Env) { return (await runtime()).default.fetch(request, env); },
} satisfies ExportedHandler<Env>;

// Runtime registration and forwarding only. State and decisions live in the
// service implementation; the gate completes initialization before any event.
export class ProjectRoom extends DurableObject<Env> {
  #ready: Promise<import('./runtime').ProjectRoom>;
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    this.#ready = ctx.blockConcurrencyWhile(async () => new (await runtime()).ProjectRoom(ctx, env));
  }
  async fetch(request: Request) { return (await this.#ready).fetch(request); }
  async webSocketMessage(socket: WebSocket, message: ArrayBuffer | string) { (await this.#ready).webSocketMessage(socket, message); }
  async webSocketClose(socket: WebSocket) { (await this.#ready).webSocketClose(socket); }
  async webSocketError(socket: WebSocket) { (await this.#ready).webSocketError(socket); }
  async getAssetMetadata(kind: AssetKind, id: string) { return (await this.#ready).getAssetMetadata(kind, id); }
  async beginAssetUpload(room: string, kind: AssetKind) { return (await this.#ready).beginAssetUpload(room, kind); }
  async finishAssetUpload(key: string, digest: string, mime: string, size: number) { return (await this.#ready).finishAssetUpload(key, digest, mime, size); }
  async discardAssetUpload(key: string) { return (await this.#ready).discardAssetUpload(key); }
  async alarm() { return (await this.#ready).alarm(); }
  async saveImage(room: string, bytes: Uint8Array<ArrayBuffer>, mime: string) { return (await this.#ready).saveImage(room, bytes, mime); }
  async propose(input: AiRequest) { return (await this.#ready).propose(input); }
}

export class AuthRecord extends DurableObject<Env> {
  #ready: Promise<import('./runtime').AuthRecord>;
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    this.#ready = ctx.blockConcurrencyWhile(async () => new (await runtime()).AuthRecord(ctx, env));
  }
  async put(value: AuthRecordValue) { return (await this.#ready).put(value); }
  async getSession(now: number) { return (await this.#ready).getSession(now); }
  async takeFlow(provider: AuthProvider, browserHash: string, origin: string, now: number) { return (await this.#ready).takeFlow(provider, browserHash, origin, now); }
  async erase() { return (await this.#ready).erase(); }
  async alarm() { return (await this.#ready).alarm(); }
}

export class UserAccount extends DurableObject<Env> {
  #ready: Promise<import('./runtime').UserAccount>;
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    this.#ready = ctx.blockConcurrencyWhile(async () => new (await runtime()).UserAccount(ctx, env));
  }
  async listProjects() { return (await this.#ready).listProjects(); }
  async putProject(project: AccountProject) { return (await this.#ready).putProject(project); }
  async deleteProject(room: string) { return (await this.#ready).deleteProject(room); }
}
