import { expect, it } from 'vitest';
import * as Y from 'yjs';
import { makeBlankScene, makeDemoProject } from '../shared/demo';
import { initializeDocument, getShared, readProject, applyChanges, LOCAL_ORIGIN } from '../shared/document';
import { parseProjectFile } from '../shared/project-file';
import { duplicateComposition, deleteComposition } from '../src/editor/structure';
import { renameScene } from '../src/editor/scenes';
import { EditorStore } from '../src/editor/store';
import { EditorUndoManager } from '../src/editor/undo';

it('appends independent Composition state in one update and Undo preserves offline source edits', () => {
  const doc = new Y.Doc(); initializeDocument(doc, makeDemoProject());
  const peer = new Y.Doc(); Y.applyUpdate(peer, Y.encodeStateAsUpdate(doc));
  const undoManager = new EditorUndoManager(doc);
  const store = Object.assign(Object.create(EditorStore.prototype), { doc, undoManager }) as EditorStore;
  const before = store.scene('scene-1');
  const sourceId = before.compositionOrder.at(-1)!;
  const sourcePath = ['scenes', 'scene-1', 'compositions', sourceId, 'states', 'circle'];
  const originalMap = getShared(doc, sourcePath);
  const updates: unknown[] = [];
  doc.on('update', (_update, origin) => { updates.push(origin); parseProjectFile(JSON.stringify(readProject(doc))); });
  try {
    const id = store.addComposition('scene-1');
    const addedPath = ['scenes', 'scene-1', 'compositions', id, 'states', 'circle'];
    const current = store.scene('scene-1');
    expect(updates).toEqual([LOCAL_ORIGIN]);
    expect(undoManager.undoStack).toHaveLength(1);
    expect(current.compositions[id].states).toEqual(before.compositions[sourceId].states);
    expect(getShared(doc, addedPath)).toBeInstanceOf(Y.Map);
    expect(getShared(doc, addedPath)).not.toBe(originalMap);
    expect(getShared(doc, [...addedPath, 'path', 'c1'])).not.toBe(getShared(doc, [...sourcePath, 'path', 'c1']));
    expect(current.compositions[sourceId].states).toBe(before.compositions[sourceId].states);
    const incoming = Object.values(current.transitions).find(transition => transition.toId === id)!;
    expect(incoming).toMatchObject({ fromId: sourceId, duration: 800 });
    expect(Object.keys(incoming.tracks).sort()).toEqual(Object.keys(before.objects).sort());
    expect(Object.values(incoming.tracks).every(track => track.implicit && track.start === 0 && track.duration === 800)).toBe(true);
    applyChanges(peer, [{ path: [...sourcePath, 'x'], value: 888 }]);
    Y.applyUpdate(doc, Y.encodeStateAsUpdate(peer));
    store.undo();
    expect(store.scene('scene-1').compositionOrder).toEqual(before.compositionOrder);
    expect(getShared(doc, sourcePath)).toBe(originalMap);
    expect(store.scene('scene-1').compositions[sourceId].states.circle.x).toBe(888);
    store.redo();
    expect(store.scene('scene-1').compositionOrder).toEqual([...before.compositionOrder, id]);
    expect(store.scene('scene-1').compositions[id].states).toEqual(before.compositions[sourceId].states);
    expect(store.scene('scene-1').compositions[sourceId].states.circle.x).toBe(888);
  } finally { undoManager.destroy(); doc.destroy(); peer.destroy(); }
});

it.each(['scene', 'composition'] as const)('revives the retained %s only as part of an undoable append', kind => {
  const doc = new Y.Doc(); initializeDocument(doc, makeDemoProject());
  const path = kind === 'scene' ? ['scenes'] : ['scenes', 'scene-1', 'compositions'];
  const entries = getShared(doc, path) as Y.Map<Y.Map<unknown>>;
  entries.forEach(entry => entry.set('deleted', true));
  const retainedId = kind === 'scene' ? readProject(doc)!.sceneOrder[0] : readProject(doc)!.scenes['scene-1'].compositionOrder[0];
  const retained = entries.get(retainedId)!;
  const undoManager = new EditorUndoManager(doc);
  const store = Object.assign(Object.create(EditorStore.prototype), { doc, undoManager }) as EditorStore;
  const order = () => kind === 'scene' ? store.project().sceneOrder : store.scene('scene-1').compositionOrder;
  try {
    const id = kind === 'scene' ? store.addScene() : store.addComposition('scene-1');
    expect(retained.get('deleted')).toBe(false);
    expect(order()).toEqual([retainedId, id]);
    expect(undoManager.undoStack).toHaveLength(1);
    parseProjectFile(JSON.stringify(readProject(doc)));
    store.undo();
    expect(retained.get('deleted')).toBe(true);
    expect(order()).toEqual([retainedId]);
    store.redo();
    expect(retained.get('deleted')).toBe(false);
    expect(order()).toEqual([retainedId, id]);
    parseProjectFile(JSON.stringify(readProject(doc)));
  } finally { undoManager.destroy(); doc.destroy(); }
});

it('preserves native preparation errors without publishing a partial Composition or reviving its source', () => {
  const doc = new Y.Doc(), project = makeDemoProject();
  project.scenes['scene-1'] = makeBlankScene('scene-1', 'Scene 1');
  initializeDocument(doc, project);
  const source = getShared(doc, ['scenes', 'scene-1', 'compositions', 'scene-1-comp-1']) as Y.Map<unknown>;
  source.set('deleted', true);
  const undoManager = new EditorUndoManager(doc);
  const store = Object.assign(Object.create(EditorStore.prototype), { doc, undoManager }) as EditorStore;
  const failure = new Error('map preparation failed');
  let allocations = 0;
  const FaultMap = new Proxy(Y.Map, { construct(target, args, newTarget) {
    if (++allocations === 3) throw failure;
    return Reflect.construct(target, args, newTarget);
  } });
  Object.defineProperty(store, 'runtime', { value: { ...store.runtime, Y: { ...Y, Map: FaultMap } } });
  const before = doc.getMap('project').toJSON(), vector = Y.encodeStateVector(doc);
  let updates = 0;
  doc.on('update', () => updates++);
  try {
    let caught: unknown;
    try { store.addComposition('scene-1'); } catch (error) { caught = error; }
    expect(caught).toBe(failure);
    expect(doc.getMap('project').toJSON()).toEqual(before);
    expect(Y.encodeStateVector(doc)).toEqual(vector);
    expect(updates).toBe(0);
    expect(undoManager.canUndo()).toBe(false);
  } finally { undoManager.destroy(); doc.destroy(); }
});

it.each(['scene', 'composition'] as const)('prepares the %s order parent before creation can publish any maps', kind => {
  const doc = new Y.Doc(); initializeDocument(doc, makeDemoProject());
  const undoManager = new EditorUndoManager(doc);
  const store = Object.assign(Object.create(EditorStore.prototype), { doc, undoManager }) as EditorStore;
  const path = kind === 'scene' ? [] : ['scenes', 'scene-1'];
  const root = kind === 'scene' ? doc.getMap('project') : getShared(doc, path) as Y.Map<unknown>;
  const key = kind === 'scene' ? 'sceneOrder' : 'compositionOrder';
  // Keep a readable snapshot but replace the shared array with a remote/plain value.
  root.set(key, (root.get(key) as Y.Array<string>).toArray());
  const before = doc.getMap('project').toJSON(), vector = Y.encodeStateVector(doc);
  try {
    expect(() => kind === 'scene' ? store.addScene() : store.addComposition('scene-1')).toThrow();
    expect(doc.getMap('project').toJSON()).toEqual(before);
    expect(Y.encodeStateVector(doc)).toEqual(vector);
    expect(undoManager.canUndo()).toBe(false);
  } finally { undoManager.destroy(); doc.destroy(); }
});

it('prepares the bridge parent before a Composition deletion can mutate shared data', () => {
  const doc = new Y.Doc(); initializeDocument(doc, makeDemoProject());
  const middle = duplicateComposition(doc, 'scene-1', 'comp-1');
  const compositions = getShared(doc, ['scenes', 'scene-1', 'compositions']) as Y.Map<unknown>;
  const next = compositions.get('comp-2') as Y.Map<unknown>;
  // Simulate an imported/remote plain record where the operation needs a shared parent.
  compositions.set('comp-2', next.toJSON());
  const before = doc.getMap('project').toJSON(), vector = Y.encodeStateVector(doc);
  expect(() => deleteComposition(doc, 'scene-1', middle)).toThrow('Composition');
  expect(doc.getMap('project').toJSON()).toEqual(before);
  expect(Y.encodeStateVector(doc)).toEqual(vector);
  doc.destroy();
});

it('keeps JavaScript-compatible UTF-16 name limits and Unicode whitespace handling', () => {
  const doc = new Y.Doc(); initializeDocument(doc, makeDemoProject());
  for (const name of ['  日本語の Scene  ', '\u3000名前\u3000', '\ufeff名前\ufeff', '😀'.repeat(150), '\u0085Name\u0085']) {
    renameScene(doc, 'scene-1', name);
    expect((getShared(doc, ['scenes', 'scene-1']) as Y.Map<unknown>).get('name')).toBe(name.trim().slice(0, 200));
  }
  doc.destroy();
});
