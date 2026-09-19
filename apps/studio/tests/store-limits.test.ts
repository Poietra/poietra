import { expect, test } from 'vitest';
import * as Y from 'yjs';
import { makeBlankScene } from '../shared/demo';
import { initializeDocument, readProject } from '../shared/document';
import { EditorStore } from '../src/editor/store';
import { EditorUndoManager } from '../src/editor/undo';

test.each(['objects', 'compositions'] as const)('manual creation respects the portable %s limit before writing or recording Undo', kind => {
  const scene = makeBlankScene('scene-limit', 'Scene');
  if (kind === 'objects') for (let i = 0; i < 500; i++) {
    const id = `object-${i}`;
    scene.objects[id] = { id, name: id, kind: 'circle', order: i, locked: false, groupId: null };
  }
  else for (let i = 1; i < 100; i++) {
    const id = `composition-${i}`;
    scene.compositionOrder.push(id);
    scene.compositions[id] = { id, name: id, duration: 1000, accent: '#ffffff', states: {} };
  }
  const doc = new Y.Doc();
  try {
    initializeDocument(doc, { version: 1, name: 'Limits', sceneOrder: [scene.id], scenes: { [scene.id]: scene } });
    const undoManager = new EditorUndoManager(doc);
    const store = Object.assign(Object.create(EditorStore.prototype), { doc, undoManager }) as EditorStore;
    const before = readProject(doc), clock = Y.encodeStateVector(doc);
    expect(() => kind === 'objects' ? store.addObject(scene.id, scene.compositionOrder[0], 'circle') : store.addComposition(scene.id)).toThrow(kind === 'objects' ? '500' : '100');
    expect(Y.encodeStateVector(doc)).toEqual(clock);
    expect(readProject(doc)).toEqual(before);
    expect(undoManager.canUndo()).toBe(false);
  } finally { doc.destroy(); }
});
