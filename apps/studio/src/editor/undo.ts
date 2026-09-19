import * as Y from 'yjs';
import { LOCAL_ORIGIN } from '../../shared/document';
import { createSession, destroySession, sessionCounts, undo, redo, rollbackGesture as rollback } from '../../../../_build/js/release/build/browser_undo/browser_undo.js';

// The subclass is an npm identity adapter. Dependency planning, peer tracking,
// history filtering and gesture ownership live in MoonBit.
export class EditorUndoManager extends Y.UndoManager {
  readonly moon: ReturnType<typeof createSession>;
  constructor(doc: Y.Doc) {
    super(doc.getMap('project'), { trackedOrigins: new Set([LOCAL_ORIGIN]), captureTimeout: 400 });
    this.moon = createSession(this, Y);
  }
  get lastUndoPreservedAudioTracks(): number { return sessionCounts(this.moon).audioTracks; }
  get lastUndoPreservedObjects(): number { return sessionCounts(this.moon).objects; }
  get lastUndoPreservedDurations(): number { return sessionCounts(this.moon).durations; }
  get lastUndoPreservedCompositions(): number { return sessionCounts(this.moon).compositions; }
  override destroy() { destroySession(this.moon); super.destroy(); }
}

export function undoPreservingPeerTracks(manager: EditorUndoManager): number { return undo(manager.moon); }
export function redoPreservingPeerDurations(manager: EditorUndoManager): number { return redo(manager.moon); }
export function rollbackGesture(manager: EditorUndoManager, expected: object): boolean { return rollback(manager.moon, expected); }
