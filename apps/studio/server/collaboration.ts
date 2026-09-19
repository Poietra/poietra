import * as Y from 'yjs';
import * as sync from 'y-protocols/sync';
import * as awareness from 'y-protocols/awareness';
import type { WebSocket } from 'ws';
import * as moon from '../../../_build/js/release/build/node_rooms/node_rooms.js';

export const ROOM_PATTERN = /^[a-zA-Z0-9_-]{16,80}$/;
export interface Room {
  readonly id: string;
  readonly doc: Y.Doc;
  readonly awareness: awareness.Awareness;
  readonly connections: Map<WebSocket, Set<number>>;
  aiBusy: boolean;
  aiLastRequest: number;
  persist(): boolean;
  dispose(): boolean;
  connect(socket: WebSocket): void;
}
const registry = moon.createRegistry({ Y, sync, awareness });
export const Room: { new(id: string): Room } = registry.Room;
export const rooms: Map<string, Room> = registry.rooms;
export const getRoom: (id: string) => Room = registry.getRoom;
