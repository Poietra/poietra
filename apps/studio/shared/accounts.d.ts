export type AuthProvider = 'google' | 'github';
export interface AccountUser {
    /** Stable, provider-scoped Poietra account ID. Never a room owner or presence ID. */
    id: string;
    /** Private provider profile name; independent of the browser's collaboration display name. */
    name: string;
    provider: AuthProvider;
}
export interface AuthSession {
    user: AccountUser | null;
    providers: Record<AuthProvider, boolean>;
}
/** Private bookmarks, separate from the shared project document. Removing one never deletes a room. */
export interface AccountProject {
    roomId: string;
    name: string;
    /** Last shortcut refresh, not the shared document's last edit time. */
    updatedAt: number;
}
export type ProjectListIntent = 'visit' | 'remember';
