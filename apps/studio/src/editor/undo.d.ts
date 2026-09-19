import * as Y from 'yjs';
import { createSession } from '../../../../_build/js/release/build/browser_undo/browser_undo.js';
export declare class EditorUndoManager extends Y.UndoManager {
    readonly moon: ReturnType<typeof createSession>;
    constructor(doc: Y.Doc);
    get lastUndoPreservedAudioTracks(): number;
    get lastUndoPreservedObjects(): number;
    get lastUndoPreservedDurations(): number;
    get lastUndoPreservedCompositions(): number;
    destroy(): void;
}
export declare function undoPreservingPeerTracks(manager: EditorUndoManager): number;
export declare function redoPreservingPeerDurations(manager: EditorUndoManager): number;
export declare function rollbackGesture(manager: EditorUndoManager, expected: object): boolean;
