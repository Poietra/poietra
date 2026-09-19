import * as Y from "yjs";
import * as sync from "y-protocols/sync";
import * as awareness from "y-protocols/awareness";
import * as moon from "../../../_build/js/release/build/node_rooms/node_rooms.js";
export const ROOM_PATTERN = /^[a-zA-Z0-9_-]{16,80}$/;
const registry = moon.createRegistry({ Y, sync, awareness });
export const Room = registry.Room;
export const rooms = registry.rooms;
export const getRoom = registry.getRoom;
