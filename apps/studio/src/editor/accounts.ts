import type { AccountProject, AuthSession } from '../../shared/accounts';
import { loginUrl as url, useAccountProjects as useAccounts } from '../../../../_build/js/release/build/ui/ui.js';
export const loginUrl: (provider: 'google' | 'github', roomId: string) => string = url;
export const useAccountProjects: (roomId: string, name: string, ready: boolean, open: boolean) => { session: AuthSession | null; projects: AccountProject[]; loading: boolean; listLoading: boolean; pending: string; error: string; refreshSession(): Promise<void>; refreshProjects(): Promise<void>; remember(): Promise<void>; remove(roomId: string): Promise<void>; logout(): Promise<void> } = useAccounts;
