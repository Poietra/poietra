import { DurableObject } from "cloudflare:workers";
// Wrangler bundles this import into a deferred initializer. MoonBit's per-module
// hash seed needs a request/DO context; workerd disallows global random I/O.
const runtime = () => import("./runtime.js");
export default {
    async fetch(request, env) { return (await runtime()).default.fetch(request, env); },
};
// Runtime registration and forwarding only. State and decisions live in the
// service implementation; the gate completes initialization before any event.
export class ProjectRoom extends DurableObject {
    #ready;
    constructor(ctx, env) {
        super(ctx, env);
        this.#ready = ctx.blockConcurrencyWhile(async () => new (await runtime()).ProjectRoom(ctx, env));
    }
    async fetch(request) { return (await this.#ready).fetch(request); }
    async webSocketMessage(socket, message) { (await this.#ready).webSocketMessage(socket, message); }
    async webSocketClose(socket) { (await this.#ready).webSocketClose(socket); }
    async webSocketError(socket) { (await this.#ready).webSocketError(socket); }
    async getAssetMetadata(kind, id) { return (await this.#ready).getAssetMetadata(kind, id); }
    async beginAssetUpload(room, kind) { return (await this.#ready).beginAssetUpload(room, kind); }
    async finishAssetUpload(key, digest, mime, size) { return (await this.#ready).finishAssetUpload(key, digest, mime, size); }
    async discardAssetUpload(key) { return (await this.#ready).discardAssetUpload(key); }
    async alarm() { return (await this.#ready).alarm(); }
    async saveImage(room, bytes, mime) { return (await this.#ready).saveImage(room, bytes, mime); }
    async propose(input) { return (await this.#ready).propose(input); }
}
export class AuthRecord extends DurableObject {
    #ready;
    constructor(ctx, env) {
        super(ctx, env);
        this.#ready = ctx.blockConcurrencyWhile(async () => new (await runtime()).AuthRecord(ctx, env));
    }
    async put(value) { return (await this.#ready).put(value); }
    async getSession(now) { return (await this.#ready).getSession(now); }
    async takeFlow(provider, browserHash, origin, now) { return (await this.#ready).takeFlow(provider, browserHash, origin, now); }
    async erase() { return (await this.#ready).erase(); }
    async alarm() { return (await this.#ready).alarm(); }
}
export class UserAccount extends DurableObject {
    #ready;
    constructor(ctx, env) {
        super(ctx, env);
        this.#ready = ctx.blockConcurrencyWhile(async () => new (await runtime()).UserAccount(ctx, env));
    }
    async listProjects() { return (await this.#ready).listProjects(); }
    async putProject(project) { return (await this.#ready).putProject(project); }
    async deleteProject(room) { return (await this.#ready).deleteProject(room); }
}
