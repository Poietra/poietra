import type { AccountProject, AuthProvider, ProjectListIntent } from '../shared/accounts';
import type { AuthFlow, AuthRecordValue, AuthRepository, AuthService, StoredSession } from '../server/auth';
export interface AuthRecord {
    put(value: AuthRecordValue): Promise<void>;
    getSession(now: number): StoredSession | null;
    takeFlow(provider: AuthProvider, browserHash: string, origin: string, now: number): AuthFlow | null;
    erase(): Promise<void>;
    alarm(): Promise<void>;
}
export declare const AuthRecord: {
    new (ctx: DurableObjectState, env: Env): AuthRecord;
};
export interface UserAccount {
    listProjects(): AccountProject[];
    putProject(project: AccountProject, intent?: ProjectListIntent): boolean;
    deleteProject(roomId: string): void;
}
export declare const UserAccount: {
    new (ctx: DurableObjectState, env: Env): UserAccount;
};
export declare const workerAuthRepository: (env: Env) => AuthRepository;
export declare const workerAuth: (env: Env) => AuthService;
