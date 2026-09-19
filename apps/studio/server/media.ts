import type { IncomingMessage, ServerResponse } from 'node:http';
import * as moon from '../../../_build/js/release/build/node_assets/node_assets.js';

export const handleMedia: (request: IncomingMessage, response: ServerResponse, pathname: string) => Promise<boolean> = moon.handleMedia;
