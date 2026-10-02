import { expect, test } from 'vitest';
import * as Y from 'yjs';
import { makeBlankScene, makeDemoProject } from '../shared/demo';
import { applyChanges, initializeDocument, readProject } from '../shared/document';
import { EditorStore } from '../src/editor/store';
import { EditorUndoManager } from '../src/editor/undo';
import { duplicateComposition } from '../src/editor/structure';

test('canvas dimensions validate the entire edit before publication and Undo', () => {
  const doc = new Y.Doc();
  try {
    initializeDocument(doc, makeDemoProject());
    const undoManager = new EditorUndoManager(doc);
    const store = Object.assign(Object.create(EditorStore.prototype), { doc, undoManager }) as EditorStore;
    const before = readProject(doc), clock = Y.encodeStateVector(doc);
    for (const height of [0, -1, 8193, 720.5, NaN, Infinity, '1080', null]) {
      expect(() => store.setScene('scene-1', { background: '#ff0000', width: 3840, height } as never)).toThrow('1〜8192');
      expect(Y.encodeStateVector(doc)).toEqual(clock);
      expect(readProject(doc)).toEqual(before);
      expect(undoManager.canUndo()).toBe(false);
    }
  } finally { doc.destroy(); }
});

test('canvas presets keep every pose and track while Undo preserves peer dimensions', () => {
  const doc = new Y.Doc(), peer = new Y.Doc();
  try {
    initializeDocument(doc, makeDemoProject());
    const undoManager = new EditorUndoManager(doc);
    const store = Object.assign(Object.create(EditorStore.prototype), { doc, undoManager }) as EditorStore;
    const before = store.scene('scene-1');
    store.setScene('scene-1', { width: 720, height: 1280 });
    expect(store.scene('scene-1')).toEqual({ ...before, width: 720, height: 1280 });
    expect(undoManager.undoStack).toHaveLength(1);
    Y.applyUpdate(peer, Y.encodeStateAsUpdate(doc));
    applyChanges(peer, [{ path: ['scenes', 'scene-1', 'height'], value: 1600 }], 'peer');
    Y.applyUpdate(doc, Y.encodeStateAsUpdate(peer));
    store.undo();
    expect(store.scene('scene-1')).toEqual({ ...before, height: 1600 });
    store.redo();
    expect(store.scene('scene-1')).toEqual({ ...before, width: 720, height: 1600 });
  } finally { doc.destroy(); peer.destroy(); }
});

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
    if (kind === 'compositions') expect(() => duplicateComposition(doc, scene.id, scene.compositionOrder[0])).toThrow('100');
    expect(Y.encodeStateVector(doc)).toEqual(clock);
    expect(readProject(doc)).toEqual(before);
    expect(undoManager.canUndo()).toBe(false);
  } finally { doc.destroy(); }
});

test('manual image creation validates before publication and retains metadata through Undo/Redo', () => {
  const scene = makeBlankScene('image-scene', 'Scene');
  const doc = new Y.Doc();
  try {
    initializeDocument(doc, { version: 1, name: 'Images', sceneOrder: [scene.id], scenes: { [scene.id]: scene } });
    const undoManager = new EditorUndoManager(doc);
    const store = Object.assign(Object.create(EditorStore.prototype), { doc, undoManager }) as EditorStore;
    const cid = scene.compositionOrder[0], clock = Y.encodeStateVector(doc);
    expect(() => store.addObject(scene.id, cid, 'image')).toThrow();
    expect(Y.encodeStateVector(doc)).toEqual(clock);
    expect(undoManager.canUndo()).toBe(false);
    const image = { src: `/api/rooms/${crypto.randomUUID()}/images/${'b'.repeat(64)}`, width: 100, height: 50 };
    const id = store.addObject(scene.id, cid, 'image', { width: 80, height: 40 }, image, 'Image'.repeat(50));
    expect(store.scene(scene.id).objects[id].image).toEqual(image);
    expect(store.scene(scene.id).objects[id].name).toHaveLength(200);
    store.undo(); expect(store.scene(scene.id).objects[id]).toBeUndefined();
    store.redo(); expect(store.scene(scene.id).objects[id].image).toEqual(image);
  } finally { doc.destroy(); }
});
