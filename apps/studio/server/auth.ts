import * as moon from '../../../_build/js/release/build/auth_service/auth_service.js';
import type { AccountProject, AccountUser, AuthProvider, AuthSession } from '../shared/accounts';

export const AUTH_FLOW_TTL = 10 * 60 * 1000;
export const AUTH_SESSION_TTL = 7 * 24 * 60 * 60 * 1000;
export const ACCOUNT_PROJECT_LIMIT = 500;
export interface AuthConfig {
  AUTH_ORIGIN?: string;
  GOOGLE_CLIENT_ID?: string; GOOGLE_CLIENT_SECRET?: string;
  GITHUB_CLIENT_ID?: string; GITHUB_CLIENT_SECRET?: string;
}
export interface AuthFlow { kind: 'flow'; provider: AuthProvider; browserHash: string; verifier: string; origin: string; returnTo: string; expiresAt: number }
export interface StoredSession { kind: 'session'; user: AccountUser; expiresAt: number }
export type AuthRecordValue = AuthFlow | StoredSession;
export interface AuthRepository {
  putRecord(key: string, value: AuthRecordValue): Promise<void>;
  getSession(key: string, now: number): Promise<StoredSession | null>;
  /** Compare and consume atomically, before any external token exchange. */
  takeFlow(key: string, provider: AuthProvider, browserHash: string, origin: string, now: number): Promise<AuthFlow | null>;
  deleteRecord(key: string): Promise<void>;
  listProjects(userId: string): Promise<AccountProject[]>;
  putProject(userId: string, project: AccountProject): Promise<boolean>;
  deleteProject(userId: string, roomId: string): Promise<void>;
}

export interface AuthService { handle(request: Request): Promise<Response | null> }
export const AuthService: { new(config: AuthConfig, repository: AuthRepository, transport?: typeof fetch, now?: () => number): AuthService } = moon.authServiceClass();
export const authHash: (value: string) => Promise<string> = moon.authHash;
export const safeReturnTo: (value: string | null, origin: string) => string = moon.safeReturnTo;
