import type { IncomingMessage, ServerResponse } from 'node:http';
export declare const saveRoomImage: (room: string, bytes: Uint8Array<ArrayBuffer>) => Promise<string>;
export declare const handleImages: (request: IncomingMessage, response: ServerResponse, pathname: string) => Promise<boolean>;
