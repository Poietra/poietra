import * as Y from 'yjs';
import * as awareness from 'y-protocols/awareness';
import type { WebSocket } from 'ws';
export declare const ROOM_PATTERN: RegExp;
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
export declare const Room: {
    new (id: string): Room;
};
export declare const rooms: Map<string, Room>;
export declare const getRoom: (id: string) => Room;
