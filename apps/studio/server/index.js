/** Native entry point: application routing and resource lifetimes are MoonBit. */
import { createServer } from "node:http";
import { WebSocketServer } from "ws";
import { aiRuntime, createEditProposal } from "./ai.js";
import { getRoom, rooms } from "./collaboration.js";
import { startServer } from "../../../_build/js/release/build/node_server/node_server.js";
await startServer({
    createServer, WebSocketServer, registry: { getRoom, rooms }, ai: aiRuntime, createEditProposal,
    loadVite: async (options) => (await import("vite")).createServer(options),
});
