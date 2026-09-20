import type { AccountProject, AccountUser, AuthProvider, ProjectListIntent } from '../shared/accounts';
export declare const AUTH_FLOW_TTL: number;
export declare const AUTH_SESSION_TTL: number;
export declare const ACCOUNT_PROJECT_LIMIT = 500;
export interface AuthConfig {
    AUTH_ORIGIN?: string;
    GOOGLE_CLIENT_ID?: string;
    GOOGLE_CLIENT_SECRET?: string;
    GITHUB_CLIENT_ID?: string;
    GITHUB_CLIENT_SECRET?: string;
}
export interface AuthFlow {
    kind: 'flow';
    provider: AuthProvider;
    browserHash: string;
    verifier: string;
    origin: string;
    returnTo: string;
    expiresAt: number;
}
export interface StoredSession {
    kind: 'session';
    user: AccountUser;
    expiresAt: number;
}
export type AuthRecordValue = AuthFlow | StoredSession;
export interface AuthRepository {
    putRecord(key: string, value: AuthRecordValue): Promise<void>;
    getSession(key: string, now: number): Promise<StoredSession | null>;
    /** Compare and consume atomically, before any external token exchange. */
    takeFlow(key: string, provider: AuthProvider, browserHash: string, origin: string, now: number): Promise<AuthFlow | null>;
    deleteRecord(key: string): Promise<void>;
    listProjects(userId: string): Promise<AccountProject[]>;
    /** Visits respect a persisted dismissal; explicit remembering restores it. */
    putProject(userId: string, project: AccountProject, intent?: ProjectListIntent): Promise<boolean>;
    deleteProject(userId: string, roomId: string): Promise<void>;
}
export interface AuthService {
    handle(request: Request): Promise<Response | null>;
}
export declare const AuthService: {
    new (config: AuthConfig, repository: AuthRepository, transport?: typeof fetch, now?: () => number): AuthService;
};
export declare const authHash: (value: string) => Promise<string>;
export declare const safeReturnTo: (value: string | null, origin: string) => string;
