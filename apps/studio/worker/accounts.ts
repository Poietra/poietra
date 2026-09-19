import * as moon from '../../../_build/js/release/build/worker_accounts/worker_accounts.js';
import type { AccountProject, AuthProvider } from '../shared/accounts';
import type { AuthFlow, AuthRecordValue, AuthRepository, AuthService, StoredSession } from '../server/auth';

export interface AuthRecord {
  put(value: AuthRecordValue): Promise<void>;
  getSession(now: number): StoredSession | null;
  takeFlow(provider: AuthProvider, browserHash: string, origin: string, now: number): AuthFlow | null;
  erase(): Promise<void>;
  alarm(): Promise<void>;
}
export const AuthRecord: { new(ctx: DurableObjectState, env: Env): AuthRecord } = moon.authRecordClass();
export interface UserAccount {
  listProjects(): AccountProject[];
  putProject(project: AccountProject): boolean;
  deleteProject(roomId: string): void;
}
export const UserAccount: { new(ctx: DurableObjectState, env: Env): UserAccount } = moon.userAccountClass();
export const workerAuthRepository: (env: Env) => AuthRepository = moon.workerAuthRepository;
export const workerAuth: (env: Env) => AuthService = moon.workerAuth;
