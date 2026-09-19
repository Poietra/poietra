import { expect, test } from 'vitest';
import * as Y from 'yjs';
import { makeDemoProject } from '../shared/demo';
import { applyChanges, initializeDocument, readProject } from '../shared/document';
import { EditorUndoManager, undoPreservingPeerTracks } from '../src/editor/undo';

test('a native Undo failure restores both history and the temporary dependency filter', () => {
  const alice = new Y.Doc(), bob = new Y.Doc();
  try {
    initializeDocument(alice, makeDemoProject());
    const manager = new EditorUndoManager(alice);
    const base = ['scenes', 'scene-1', 'transitions', 'transition-1'];
    applyChanges(alice, [{ path: ['name'], value: 'Earlier edit' }]);
    manager.stopCapturing();
    applyChanges(alice, [{ path: [...base, 'duration'], value: 2000 }]);
    manager.stopCapturing();
    Y.applyUpdate(bob, Y.encodeStateAsUpdate(alice));
    applyChanges(bob, [{ path: [...base, 'tracks', 'circle', 'duration'], value: 1800 }]);
    Y.applyUpdate(alice, Y.encodeStateAsUpdate(bob));
    const before = readProject(alice), stack = [...manager.undoStack];
    const action = stack.at(-1)!, deletions = action.deletions, filter = manager.deleteFilter;
    const nativeUndo = manager.undo, failure = new Error('Yjs host failure');
    manager.undo = () => {
      expect(manager.undoStack).toHaveLength(1);
      expect(action.deletions).not.toBe(deletions);
      expect(manager.deleteFilter).not.toBe(filter);
      throw failure;
    };
    expect(() => undoPreservingPeerTracks(manager)).toThrow(failure);
    expect(manager.undoStack).toEqual(stack);
    expect(manager.deleteFilter).toBe(filter);
    expect(action.deletions).toBe(deletions);
    expect(readProject(alice)).toEqual(before);
    manager.undo = nativeUndo;
    expect(undoPreservingPeerTracks(manager)).toBe(0);
    expect(manager.lastUndoPreservedDurations).toBe(1);
    expect(readProject(alice)!.name).toBe('Earlier edit');
  } finally { alice.destroy(); bob.destroy(); }
});
