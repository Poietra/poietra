import * as Y from "yjs";
import { LOCAL_ORIGIN } from "../../shared/document.js";
import { createSession, destroySession, sessionCounts, undo, redo, rollbackGesture as rollback } from "../../../../_build/js/release/build/browser_undo/browser_undo.js";
// The subclass is an npm identity adapter. Dependency planning, peer tracking,
// history filtering and gesture ownership live in MoonBit.
export class EditorUndoManager extends Y.UndoManager {
    moon;
    constructor(doc) {
        super(doc.getMap('project'), { trackedOrigins: new Set([LOCAL_ORIGIN]), captureTimeout: 400 });
        this.moon = createSession(this, Y);
    }
    get lastUndoPreservedAudioTracks() { return sessionCounts(this.moon).audioTracks; }
    get lastUndoPreservedObjects() { return sessionCounts(this.moon).objects; }
    get lastUndoPreservedDurations() { return sessionCounts(this.moon).durations; }
    get lastUndoPreservedCompositions() { return sessionCounts(this.moon).compositions; }
    destroy() { destroySession(this.moon); super.destroy(); }
}
export function undoPreservingPeerTracks(manager) { return undo(manager.moon); }
export function redoPreservingPeerDurations(manager) { return redo(manager.moon); }
export function rollbackGesture(manager, expected) { return rollback(manager.moon, expected); }
