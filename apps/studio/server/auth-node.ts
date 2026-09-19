import type { IncomingMessage, ServerResponse } from 'node:http';
import * as moon from '../../../_build/js/release/build/node_auth/node_auth.js';
import type { AuthConfig, AuthRepository } from './auth';

export interface NodeAuthRepository extends AuthRepository { cleanup(now?: number): void }
export const NodeAuthRepository: { new(directory: string): NodeAuthRepository } = moon.nodeAuthRepositoryClass();
export const createNodeAuth: (config: AuthConfig, directory: string) => ((request: IncomingMessage, response: ServerResponse) => Promise<boolean>) & { dispose(): void } = moon.createNodeAuth;
