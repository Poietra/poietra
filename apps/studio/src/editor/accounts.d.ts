import type { AccountProject, AuthSession } from '../../shared/accounts';
export declare const loginUrl: (provider: 'google' | 'github', roomId: string) => string;
export declare const useAccountProjects: (roomId: string, name: string, ready: boolean, open: boolean) => {
    session: AuthSession | null;
    projects: AccountProject[];
    loading: boolean;
    listLoading: boolean;
    pending: string;
    error: string;
    refreshSession(): Promise<void>;
    refreshProjects(): Promise<void>;
    remember(): Promise<void>;
    remove(roomId: string): Promise<void>;
    logout(): Promise<void>;
};
