import type { IncomingMessage, ServerResponse } from 'node:http';
import type { AuthConfig, AuthRepository } from './auth';
export interface NodeAuthRepository extends AuthRepository {
    cleanup(now?: number): void;
}
export declare const NodeAuthRepository: {
    new (directory: string): NodeAuthRepository;
};
export declare const createNodeAuth: (config: AuthConfig, directory: string) => ((request: IncomingMessage, response: ServerResponse) => Promise<boolean>) & {
    dispose(): void;
};
