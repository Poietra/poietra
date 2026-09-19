import type { IncomingMessage, ServerResponse } from 'node:http';
import * as moon from '../../../_build/js/release/build/node_assets/node_assets.js';

export const saveRoomImage: (room: string, bytes: Uint8Array<ArrayBuffer>) => Promise<string> = moon.saveRoomImage;
export const handleImages: (request: IncomingMessage, response: ServerResponse, pathname: string) => Promise<boolean> = moon.handleImages;
