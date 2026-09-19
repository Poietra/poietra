import type { IncomingMessage, ServerResponse } from 'node:http';
export declare const handleMedia: (request: IncomingMessage, response: ServerResponse, pathname: string) => Promise<boolean>;
