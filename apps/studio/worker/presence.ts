import * as moon from '../../../_build/js/release/build/server_presence/server_presence.js';

interface PresenceState {
  user: { name: string; color: string };
  editor: { sceneId?: string; compositionId?: string; selectedIds: string[]; cursor: { x: number; y: number } | null };
}
export interface Presence { clientId: number; clock: number; state: PresenceState | null }

export const readPresenceUpdate: (update: Uint8Array, previous: Presence | null) => Presence | null = moon.readPresenceUpdate;
export const presenceMessage: (entries: Presence[]) => Uint8Array = moon.presenceMessage;
