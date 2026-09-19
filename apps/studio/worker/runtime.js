/** Native platform/package wiring; room state and request policy live in MoonBit. */
import * as Y from "yjs";
import * as sync from "y-protocols/sync";
import { aiRuntime, createEditProposal } from "../server/ai.js";
import * as rooms from "../../../_build/js/release/build/worker_room/worker_room.js";
import * as server from "../../../_build/js/release/build/worker_server/worker_server.js";
export { AuthRecord, UserAccount } from "./accounts.js";
const runtime = { Y, sync, ai: aiRuntime, createEditProposal };
export default {
    fetch(request, env) { return server.handleRequest(request, env, aiRuntime); },
};
export const ProjectRoom = rooms.projectRoomClass(runtime);
