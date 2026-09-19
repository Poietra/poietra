interface PresenceState {
    user: {
        name: string;
        color: string;
    };
    editor: {
        sceneId?: string;
        compositionId?: string;
        selectedIds: string[];
        cursor: {
            x: number;
            y: number;
        } | null;
    };
}
export interface Presence {
    clientId: number;
    clock: number;
    state: PresenceState | null;
}
export declare const readPresenceUpdate: (update: Uint8Array, previous: Presence | null) => Presence | null;
export declare const presenceMessage: (entries: Presence[]) => Uint8Array;
export {};
